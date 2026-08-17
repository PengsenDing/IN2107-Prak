"""Post-Installation Cockpit for SAP UCC.

Streamlit entry point that composes the post-installation workflow:
manual guides with screenshots, SAP GUI report launchers, and a fixed
allowlist of remote shell scripts executed over SSH. Connection settings
come from ``.streamlit/secrets.toml``; the script allowlist comes from
``scripts_catalog.json``. See README.md for the full setup.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import streamlit as st

from post_transport_wiki import render_post_transport_wiki
from wp2_secstore import render_wp2_secstore
from wp2_transport_system import render_wp2_transport_system
from sap_connectivity import render_connectivity_config

CATALOG_FILE = Path(__file__).with_name("scripts_catalog.json")
UI_TEXT_FILE = Path(__file__).with_name("ui_text.json")
MANUAL_STEPS_FILE = Path(__file__).with_name("manual_steps.json")
ASSETS_DIR = Path(__file__).with_name("images")
DEFAULT_TRANSPORT_CONFIG_FILE = Path(__file__).with_name("bulk-transports-gb43.json")
LOCAL_SCRIPTS_DIR = Path(__file__).with_name("scripts")
VALID_PARAMETER_TYPES = {"text", "number", "password", "select", "checkbox"}
SAP_CLIENTS = ("000", "800", "999")
ABAPGIT_STANDALONE_FILE = (
    Path(__file__).with_name("abap")
    / "vendor"
    / "zabapgit_standalone.prog.abap"
)


@dataclass(frozen=True)
class ScriptParameterDefinition:
    """One typed input field of an allowlisted script, from scripts_catalog.json."""

    name: str
    label: str
    kind: str
    default: Any
    help_text: str
    required: bool
    options: tuple[str, ...]
    flag: str | None


@dataclass(frozen=True)
class ScriptDefinition:
    """One allowlisted remote script; only these paths can be executed."""

    script_id: str
    label: str
    description: str
    path: str
    timeout_seconds: int
    parameters: tuple[ScriptParameterDefinition, ...]


@dataclass(frozen=True)
class TransferResult:
    """Outcome of copying local script files to the remote server via scp."""

    title: str
    destination: str
    sources: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


def expand_path(path: str) -> str:
    """Expand ``~`` and environment variables in a user-supplied path."""
    return os.path.expandvars(os.path.expanduser(path))


def _secret_section(name: str) -> dict[str, Any]:
    """Read one section of st.secrets, treating a missing file as empty."""
    try:
        value = st.secrets.get(name, {})
        return dict(value) if value else {}
    except Exception:
        return {}


@st.cache_data
def load_ui_text() -> dict[str, Any]:
    """Load the page title and shared UI strings from ui_text.json."""
    with UI_TEXT_FILE.open(encoding="utf-8") as handle:
        return json.load(handle)


@st.cache_data
def load_manual_guides() -> dict[str, dict[str, Any]]:
    """Load the manual guides from manual_steps.json, keyed by guide id."""
    with MANUAL_STEPS_FILE.open(encoding="utf-8") as handle:
        payload = json.load(handle)
    guides: dict[str, dict[str, Any]] = {}
    for guide in payload.get("guides", []):
        guide_id = str(guide.get("id", "")).strip()
        if not guide_id or guide_id in guides:
            raise ValueError(f"Invalid or duplicate manual guide id: {guide_id!r}")
        guides[guide_id] = guide
    return guides


def resolve_asset_path(relative_path: str) -> Path:
    """Resolve a screenshot path inside images/.

    Raises ValueError when the configured path escapes the assets
    directory, so guide configuration cannot read arbitrary files.
    """
    root = ASSETS_DIR.resolve()
    candidate = (root / relative_path).resolve()
    candidate.relative_to(root)
    return candidate


def load_config() -> dict[str, Any]:
    """Combine the script catalog with the connection settings from secrets.

    The SSH server and private-key path have no safe default, so startup
    fails with a clear message when they are missing.
    """
    with CATALOG_FILE.open("r", encoding="utf-8") as file:
        catalog = json.load(file)
    ssh = _secret_section("ssh")
    transport = _secret_section("transport")
    sap_gui = _secret_section("sap_gui")
    features = _secret_section("features")
    backup_defaults = _secret_section("hana_backup_defaults")
    required = {"server": ssh.get("server"), "private_key_path": ssh.get("private_key_path")}
    missing = [name for name, value in required.items() if not str(value or "").strip()]
    if missing:
        raise ValueError("Missing Streamlit secrets: " + ", ".join(f"ssh.{name}" for name in missing))
    return {
        "server": str(ssh["server"]),
        "ssh_key_path": str(ssh["private_key_path"]),
        "known_hosts_path": str(ssh.get("known_hosts_path", "~/.ssh/known_hosts")),
        "ssh_port": int(ssh.get("port", 22)),
        "connect_timeout_seconds": int(ssh.get("connect_timeout_seconds", 10)),
        "default_timeout_seconds": int(catalog.get("default_timeout_seconds", 300)),
        "transport_config_upload": {"remote_directory": str(transport.get("remote_directory", ""))},
        "sap_gui": sap_gui,
        "features": features,
        "hana_backup_defaults": backup_defaults,
        "scripts": catalog.get("scripts", []),
    }


def render_manual_guide(guide: dict[str, Any], *, key_prefix: str) -> bool:
    """Render one manual guide and return whether the operator confirmed it."""
    with st.container(border=True):
        st.header(str(guide.get("title", "Manual step")))
        warning = str(guide.get("warning", "")).strip()
        if warning:
            st.warning(warning)
        expanded = bool(guide.get("expanded", False))
        for number, step in enumerate(guide.get("steps", []), start=1):
            with st.expander(f"Step {number}: {step.get('title', '')}", expanded=expanded and number == 1):
                st.markdown(str(step.get("description", "")))
                image = str(step.get("image", "")).strip()
                if image:
                    try:
                        image_path = resolve_asset_path(image)
                        if image_path.is_file():
                            st.image(str(image_path), caption=str(step.get("caption", "")) or None, use_container_width=True)
                        else:
                            st.warning(f"Screenshot is missing: `{image}`")
                    except ValueError:
                        st.error("Invalid screenshot path in manual guide configuration.")
                alt = str(step.get("alt", "")).strip()
                if alt:
                    st.caption(f"Image description: {alt}")
        completion_key = str(guide.get("completion_key", f"{key_prefix}_completed"))
        completion_label = str(
            guide.get("completion_label", "I completed and verified this manual step.")
        )
        return st.checkbox(
            completion_label,
            key=completion_key,
        )


def load_scripts(config: dict[str, Any]) -> list[ScriptDefinition]:
    """Validate the catalog entries and turn them into ScriptDefinitions.

    Rejects relative script paths, unknown parameter types, and select
    parameters without options, so configuration mistakes surface at
    startup instead of at execution time.
    """
    default_timeout = int(config.get("default_timeout_seconds", 300))
    scripts: list[ScriptDefinition] = []

    for item in config["scripts"]:
        path = item["path"]
        if not path.startswith("/"):
            raise ValueError(f"Script path must be absolute: {path}")

        parameters: list[ScriptParameterDefinition] = []
        for parameter in item.get("parameters", []):
            name = parameter["name"]
            kind = parameter.get("type", "text")
            if kind not in VALID_PARAMETER_TYPES:
                raise ValueError(f"Unsupported parameter type for {item['id']}: {kind}")

            options = tuple(str(option) for option in parameter.get("options", []))
            if kind == "select" and not options:
                raise ValueError(f"Select parameter must define options: {name}")

            parameters.append(
                ScriptParameterDefinition(
                    name=name,
                    label=parameter.get("label", name.replace("_", " ").title()),
                    kind=kind,
                    default=parameter.get("default", ""),
                    help_text=parameter.get("help", ""),
                    required=bool(parameter.get("required", False)),
                    options=options,
                    flag=parameter.get("flag"),
                )
            )

        scripts.append(
            ScriptDefinition(
                script_id=item["id"],
                label=item["label"],
                description=item.get("description", ""),
                path=path,
                timeout_seconds=int(item.get("timeout_seconds", default_timeout)),
                parameters=tuple(parameters),
            )
        )

    return scripts


def format_parameter_value(parameter: ScriptParameterDefinition, raw_value: Any) -> str:
    """Convert a widget value into the string passed to the remote script."""
    if parameter.kind == "checkbox":
        return "true" if bool(raw_value) else "false"

    return str(raw_value)


def build_remote_command(command_parts: list[str]) -> str:
    """Join command parts with shell quoting so values cannot inject commands."""
    return " ".join(shlex.quote(part) for part in command_parts)


def build_script_arguments(
    script: ScriptDefinition, parameter_values: dict[str, Any]
) -> list[str]:
    """Turn entered parameter values into command-line arguments.

    Password values are intentionally excluded: they would be visible in
    the remote process list as arguments, so run_script() sends them via
    standard input instead.
    """
    arguments: list[str] = []
    for parameter in script.parameters:
        value = parameter_values[parameter.name]
        if parameter.kind == "password":
            if parameter.required and not str(value).strip():
                raise ValueError(f"Parameter '{parameter.label}' is required.")
            continue
        if parameter.flag:
            if parameter.kind == "checkbox":
                if bool(value):
                    arguments.append(parameter.flag)
                continue

            if str(value).strip() == "":
                if parameter.required:
                    raise ValueError(f"Parameter '{parameter.label}' is required.")
                continue

            arguments.extend([parameter.flag, format_parameter_value(parameter, value)])
            continue

        if parameter.required and str(value).strip() == "":
            raise ValueError(f"Parameter '{parameter.label}' is required.")

        arguments.append(format_parameter_value(parameter, value))

    return arguments


def build_ssh_command(
    config: dict[str, Any], remote_command: str
) -> list[str]:
    """Build the non-interactive ssh invocation for one remote command.

    BatchMode and strict host-key checking are fixed: the app must never
    hang on a prompt or silently accept an unknown host key.
    """
    server = config["server"]
    ssh_key_path = expand_path(config["ssh_key_path"])
    ssh_port = str(config.get("ssh_port", 22))

    return [
        "ssh",
        "-i",
        ssh_key_path,
        "-p",
        ssh_port,
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        f"UserKnownHostsFile={expand_path(config['known_hosts_path'])}",
        "-o",
        f"ConnectTimeout={int(config.get('connect_timeout_seconds', 10))}",
        "-o",
        "RequestTTY=no",
        server,
        remote_command,
    ]


def build_scp_command(
    config: dict[str, Any], sources: list[str], destination: str
) -> list[str]:
    """Build the scp invocation with the same safety options as ssh."""
    ssh_key_path = expand_path(config["ssh_key_path"])
    ssh_port = str(config.get("ssh_port", 22))

    return [
        "scp",
        "-P",
        ssh_port,
        "-i",
        ssh_key_path,
        "-p",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        f"UserKnownHostsFile={expand_path(config['known_hosts_path'])}",
        "-o",
        f"ConnectTimeout={int(config.get('connect_timeout_seconds', 10))}",
        *sources,
        destination,
    ]


def run_script(
    config: dict[str, Any],
    script: ScriptDefinition,
    script_arguments: list[str],
    secret_input: str = "",
) -> subprocess.CompletedProcess[str] | str:
    """Run one allowlisted script over SSH.

    Returns the completed process, or a human-readable error string for
    the failures an operator can act on (timeout, missing OpenSSH).
    ``secret_input`` carries password values to the remote script's stdin
    so they never appear as process arguments.
    """
    remote_command = build_remote_command([script.path, *script_arguments])
    command = build_ssh_command(config, remote_command)
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            input=(secret_input + "\n") if secret_input else None,
            timeout=script.timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return (
            f"Timeout after {script.timeout_seconds} seconds. The local SSH command "
            "was stopped. Check the remote server to verify whether the script is "
            "still running."
        )
    except FileNotFoundError:
        return (
            "The local 'ssh' command was not found. Install or enable OpenSSH Client "
            "on this notebook."
        )


def validate_transport_config(content: bytes) -> tuple[dict[str, Any], int]:
    """Parse an uploaded transport profile and return (payload, transport count).

    Raises ValueError for oversized files, invalid JSON, or a missing or
    empty ``transports`` list.
    """
    if len(content) > 2 * 1024 * 1024:
        raise ValueError("Transport configuration must not exceed 2 MB.")
    try:
        payload = json.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Upload a valid UTF-8 JSON file.") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("transports"), list):
        raise ValueError("Transport configuration must contain a 'transports' list.")
    if not payload["transports"]:
        raise ValueError("Transport configuration must contain at least one transport.")
    return payload, len(payload["transports"])


def upload_transport_config(config: dict[str, Any], sid: str, content: bytes) -> str:
    """Upload a validated transport profile and return its remote path.

    The remote directory comes from configuration and must be a safe
    absolute POSIX path; the file name is derived from the selected SID so
    each system keeps exactly one active profile.
    """
    upload_config = config.get("transport_config_upload", {})
    remote_directory = str(upload_config.get("remote_directory", "")).strip()
    if (
        not remote_directory.startswith("/")
        or ".." in remote_directory.split("/")
        or not re.fullmatch(r"/[A-Za-z0-9._/-]+", remote_directory)
    ):
        raise ValueError(
            "transport_config_upload.remote_directory must be a safe absolute POSIX "
            "path."
        )
    if not SAP_SYSTEM_ID_PATTERN.fullmatch(sid):
        raise ValueError("Selected SAP system ID is invalid.")

    remote_path = f"{remote_directory.rstrip('/')}/bulk-transports-{sid}.json"

    try:
        mkdir_result = subprocess.run(
            build_ssh_command(
                config, f"mkdir -p -- {shlex.quote(remote_directory)}"
            ),
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if mkdir_result.returncode != 0:
            raise RuntimeError(
                mkdir_result.stderr.strip()
                or "Could not create the remote upload directory."
            )

        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as temporary_file:
            temporary_file.write(content)
            temporary_path = temporary_file.name
        try:
            upload_result = subprocess.run(
                build_scp_command(
                    config,
                    [temporary_path],
                    f"{config['server']}:{remote_path}",
                ),
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
        finally:
            Path(temporary_path).unlink(missing_ok=True)
        if upload_result.returncode != 0:
            raise RuntimeError(
                upload_result.stderr.strip()
                or "Could not upload the transport configuration."
            )
    except FileNotFoundError as exc:
        raise RuntimeError(
            "OpenSSH Client (ssh and scp) must be installed on this notebook."
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("The transport configuration upload timed out.") from exc

    return remote_path

def copy_scripts_to_server(
    config: dict[str, Any], scripts: list[ScriptDefinition]
) -> TransferResult | str:
    """Copy the local copies of allowlisted scripts to /tmp/ on the server.

    Returns a TransferResult, or an error string when a local file is
    missing or scp is unavailable.
    """
    if not scripts:
        return "No scripts are configured to copy."

    local_sources: list[str] = []
    missing_sources: list[str] = []

    for script in scripts:
        local_script_path = LOCAL_SCRIPTS_DIR / Path(script.path).name
        if not local_script_path.exists():
            missing_sources.append(str(local_script_path))
            continue
        local_sources.append(str(local_script_path))

    if missing_sources:
        return f"Missing local script file(s): {', '.join(missing_sources)}"

    destination = f"{config['server']}:/tmp/"
    try:
        copy_result = subprocess.run(
            build_scp_command(config, local_sources, destination),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    except FileNotFoundError:
        return (
            "The local 'scp' command was not found. Install or enable OpenSSH Client "
            "on this notebook."
        )
    except subprocess.TimeoutExpired:
        return "Timed out while copying scripts to /tmp/."

    return TransferResult(
        title=f"Copied {len(local_sources)} script(s) to /tmp/",
        destination=destination,
        sources=tuple(local_sources),
        returncode=copy_result.returncode,
        stdout=copy_result.stdout,
        stderr=copy_result.stderr,
    )


def render_result(result: subprocess.CompletedProcess[str] | str) -> None:
    """Show a script run's outcome; a plain string means the run failed early."""
    if isinstance(result, str):
        st.error(result)
        return

    if result.returncode == 0:
        st.success(f"Finished successfully. Exit code: {result.returncode}")
    else:
        st.error(f"Finished with errors. Exit code: {result.returncode}")

    render_command_output(result.stdout, result.stderr)


def render_command_output(stdout: str, stderr: str) -> None:
    """Show captured stdout and stderr so the operator can verify the run."""
    for label, output in (("stdout", stdout), ("stderr", stderr)):
        st.subheader(label)
        st.code(output.strip() or "<empty>", language="text")


def render_transfer_result(result: TransferResult | str) -> None:
    """Show the outcome of a script copy, including the transferred files."""
    if isinstance(result, str):
        st.error(result)
        return

    if result.returncode == 0:
        st.success(result.title)
    else:
        st.error(f"{result.title} (exit code: {result.returncode})")

    st.write(f"Destination: {result.destination}")
    st.write(f"Sources: {', '.join(result.sources)}")

    render_command_output(result.stdout, result.stderr)


def render_transport_config_upload(config: dict[str, Any]) -> None:
    """Render the transport-profile upload for the selected SAP system.

    Offers the bundled GB 4.3 standard as the primary action and a file
    picker for custom profiles, then shows the remote path to enter in
    the ZBULK_TRANSPORT_IMPORT report.
    """
    st.header("Upload transport configuration to the server")
    st.caption(
        "By default, the bundled GB 4.3 configuration is used. "
        "A custom JSON file is only required for transport runs that differ from the "
        "standard bulk import."
    )
    selected_sid = default_sap_system(config)
    if not selected_sid:
        st.error("Configure at least one SAP system in sap_gui.systems first.")
        return
    result_key = f"uploaded_transport_config_{selected_sid}"

    try:
        default_content = DEFAULT_TRANSPORT_CONFIG_FILE.read_bytes()
        default_payload, default_transport_count = validate_transport_config(default_content)
        default_profile_name = str(
            default_payload.get(
                "profileName", default_payload.get("profileId", "GB 4.3")
            )
        )
        st.info(
            f"Default: **{default_profile_name}** with "
            f"**{default_transport_count}** transport requests."
        )
        if st.button(
            f"Upload GB 4.3 standard to {selected_sid}",
            type="primary",
            key="upload_default_transport_config",
        ):
            with st.spinner("Uploading transport configuration through SSH..."):
                remote_path = upload_transport_config(
                    config, selected_sid, default_content
                )
            st.session_state[result_key] = {
                "path": remote_path,
                "source": "GB 4.3 standard",
            }
    except (OSError, RuntimeError, ValueError) as exc:
        st.error(f"The bundled GB 4.3 configuration is not available: {exc}")

    with st.expander("Use a custom transport configuration"):
        st.warning(
            "Use this only if the transport list differs from the GB 4.3 standard. "
            "The upload replaces the configuration previously uploaded for this system."
        )
        uploaded_file = st.file_uploader(
            "Custom transport configuration file (.json)",
            type=["json"],
            key="custom_transport_config_upload_file",
        )
        if uploaded_file is not None:
            custom_content = uploaded_file.getvalue()
            try:
                custom_payload, custom_transport_count = validate_transport_config(
                    custom_content
                )
                custom_profile_name = str(
                    custom_payload.get(
                        "profileName",
                        custom_payload.get("profileId", "unnamed profile"),
                    )
                )
                st.success(
                    f"Valid JSON: {custom_profile_name} with "
                    f"{custom_transport_count} transport entries."
                )
                if st.button(
                    f"Upload custom configuration to {selected_sid}",
                    key="upload_custom_transport_config",
                ):
                    with st.spinner("Uploading custom transport configuration through SSH..."):
                        remote_path = upload_transport_config(
                            config, selected_sid, custom_content
                        )
                    st.session_state[result_key] = {
                        "path": remote_path,
                        "source": f"custom: {custom_profile_name}",
                    }
            except (OSError, RuntimeError, ValueError) as exc:
                st.error(str(exc))

    upload_result = st.session_state.get(result_key)
    if isinstance(upload_result, dict) and upload_result.get("path"):
        st.success(
            f"Upload completed for {selected_sid} using {upload_result['source']}. "
            "Copy this path into the SAP report:"
        )
        st.code(upload_result["path"], language="text")


def render_post_transport_guide(
    config: dict[str, Any], backup_scripts: list[ScriptDefinition]
) -> None:
    """Render only the part of the GB 4.3 wiki owned by this dashboard."""
    render_sap_report_launcher(
        config,
        title="User Configuration Client 000",
        default_report="Z_USER_CUSTOMIZATION",
        description=(
            "Opens the user configuration report in SAP GUI for client 000. "
            "It creates/assigns SAP UCC MÜNCHEN, sets initial passwords, "
            "and prepares the technical users according to the post-installation guide."
        ),
        key_prefix="user_configuration_client_000",
        client_options=("000",),
    )

    st.markdown("---")
    render_sap_report_launcher(
        config,
        title="Set Up SAP Logon Welcome Text",
        default_report="Z_WELCOME_TEXT_SHR",
        description=(
            "Choose the confirmed UCC system classification, then open the "
            "matching welcome-text automation in SAP GUI client 000. Running "
            "a different classification later overwrites the same SE61 document."
        ),
        key_prefix="welcome_text",
        client_options=("000",),
        report_options={
            "Shared": "Z_WELCOME_TEXT_SHR",
            "Exclusive": "Z_WELCOME_TEXT_EXC",
            "Development-Shared (Entwicklung-Shared)": "Z_WELCOME_TEXT_DEV",
        },
    )

    st.markdown("---")
    render_wp2_secstore()

    st.markdown("---")
    render_sap_report_launcher(
        config,
        title="Standard Jobs",
        default_report="Z_STANDARD_JOBS",
        description=(
            "Opens the Standard Jobs automation in SAP GUI for client 000. "
            "It activates Job Repository Job Automation only when inactive "
            "and leaves an already-active configuration unchanged."
        ),
        key_prefix="standard_jobs",
        client_options=("000",),
    )

    st.markdown("---")
    render_connectivity_config(config, render_sap_report_launcher)

    st.markdown("---")
    render_transport_config_upload(config)
    st.markdown("---")
    render_sap_report_launcher(
        config,
        title="Install patches / import transport requests",
        default_report="ZBULK_TRANSPORT_IMPORT",
        description=(
            "Opens the delivered SAP report. Review the transport path and execute "
            "it manually in SAP GUI."
        ),
        key_prefix="bulk_transport",
    )

    st.markdown("---")
    render_sap_report_launcher(
        config,
        title="Fix the frontend printing issue",
        default_report="ZFRONTEND_PRINT_PLAN",
        description="Opens the report in SAP GUI. Choose validation or activation there.",
        key_prefix="frontend_print",
    )

    render_post_transport_wiki(
        ("Kacheln für die Dozenten anpassen",),
    )

    st.markdown("---")
    render_sap_report_launcher(
        config,
        title="Prepare clients",
        default_report="ZCLIENT_PROVISIONING",
        description="Opens the report in SAP GUI. Review and confirm any changes there.",
        key_prefix="client_provisioning",
    )

    render_post_transport_wiki(
        ("Externe Dienste", "Einbinden ins Monitoring")
    )

    st.markdown("---")
    render_existing_os_automations(
        config,
        backup_scripts,
        "HANA backup automation",
        "Wiki script: HANA backup automation. It automates only the Storage Protect "
        "client and TDP client installation; complete the remaining wiki steps "
        "manually.",
    )

    render_post_transport_wiki(("HANA Backup einrichten",))


SAP_REPORT_PATTERN = re.compile(r"[A-Z][A-Z0-9_]{0,39}")
SAP_SYSTEM_ID_PATTERN = re.compile(r"[A-Z0-9]{3}")
SAP_HOST_PATTERN = re.compile(r"[A-Za-z0-9.-]+")


def available_sap_systems(config: dict[str, Any]) -> dict[str, str]:
    """Return the launchable SAP systems as a sorted {SID: host} mapping.

    Combines the approved systems from configuration with any
    session-added systems (when that feature is enabled) and silently
    drops entries whose SID or host fails validation.
    """
    sap_gui = config.get("sap_gui", {})

    configured_systems = (
        sap_gui.get("systems", {})
        if isinstance(sap_gui, Mapping)
        else {}
    )

    systems: dict[str, str] = {}

    if isinstance(configured_systems, Mapping):
        for sid, host in configured_systems.items():
            normalized_sid = str(sid).upper()
            normalized_host = str(host).strip()

            if (
                SAP_SYSTEM_ID_PATTERN.fullmatch(normalized_sid)
                and SAP_HOST_PATTERN.fullmatch(normalized_host)
            ):
                systems[normalized_sid] = normalized_host

    features = config.get("features", {})

    allow_session_addition = (
        bool(features.get("allow_session_system_addition", False))
        if isinstance(features, Mapping)
        else False
    )

    if allow_session_addition:
        custom_systems = st.session_state.get("custom_sap_systems", {})

        if isinstance(custom_systems, Mapping):
            systems.update(
                {
                    str(sid).upper(): str(host).strip()
                    for sid, host in custom_systems.items()
                }
            )

    if not systems:
        raise ValueError(
            "No valid SAP systems are configured in sap_gui.systems."
        )

    return dict(sorted(systems.items()))


def default_sap_system(config: dict[str, Any]) -> str:
    """Return the SID selected in the sidebar, or the first configured system."""
    selected = str(st.session_state.get("selected_sid", "")).upper()
    if selected:
        return selected
    try:
        return next(iter(available_sap_systems(config)))
    except ValueError:
        return ""


def add_sap_system(sid: str, application_server: str) -> None:
    """Validate and store a session-scoped SAP system entered in the sidebar."""
    normalized_sid = sid.strip().upper()
    normalized_host = application_server.strip().lower()
    if not SAP_SYSTEM_ID_PATTERN.fullmatch(normalized_sid):
        raise ValueError("System ID must contain exactly three uppercase letters or digits.")
    if not SAP_HOST_PATTERN.fullmatch(normalized_host):
        raise ValueError("Application server must be a hostname or IP address without spaces.")
    systems = dict(st.session_state.get("custom_sap_systems", {}))
    systems[normalized_sid] = normalized_host
    st.session_state["custom_sap_systems"] = systems


def select_sap_system(config: dict[str, Any], sid: str) -> None:
    """Store the sidebar selection and apply its HANA backup defaults."""
    normalized_sid = sid.upper()
    st.session_state["selected_sid"] = normalized_sid

    backup_defaults = config.get("hana_backup_defaults", {})
    selected_defaults = (
        backup_defaults.get(normalized_sid, {})
        if isinstance(backup_defaults, dict)
        else {}
    )
    if "sid" in selected_defaults:
        st.session_state["param_hana_backup_setup_sid"] = str(selected_defaults["sid"])


def launch_sap_report(
    config: dict[str, Any], sid: str, client: str, report: str, transaction: str = "SA38"
) -> str:
    """Open SAP GUI locally and route a report workflow through an SAP transaction."""
    normalized_report = report.strip().upper()
    normalized_transaction = transaction.strip().upper()
    if normalized_report and not SAP_REPORT_PATTERN.fullmatch(normalized_report):
        raise ValueError("Report name must contain only A-Z, 0-9, and underscores.")
    if not re.fullmatch(r"[A-Z0-9]{1,20}", normalized_transaction):
        raise ValueError("SAP transaction must contain 1 to 20 uppercase letters or digits.")
    if not re.fullmatch(r"\d{3}", client):
        raise ValueError("SAP client must have exactly three digits.")
    systems = available_sap_systems(config)
    application_server = systems.get(sid)
    if application_server is None:
        raise ValueError(f"No application server is configured for {sid}.")

    configured_executable = str(config.get("sap_gui", {}).get("executable_path", "")).strip()
    sapshcut = Path(expand_path(configured_executable)) if configured_executable else None
    if sapshcut is None or not sapshcut.is_file():
        raise RuntimeError(
            "SAP GUI shortcut program (sapshcut.exe) was not found on this notebook."
        )

    sap_gui = config.get("sap_gui", {})
    instance_number = str(sap_gui.get("instance_number", "00"))
    if not re.fullmatch(r"\d{2}", instance_number):
        raise ValueError("sap_gui.instance_number must have exactly two digits.")
    gui_connection = f"/H/{application_server}/S/32{instance_number}"

    command = [
        str(sapshcut),
        f"-system={sid}",
        f"-gui={gui_connection}",
        f"-client={client}",
    ]
    if normalized_report:
        # SAP transaction codes are limited to 20 characters, whereas report names
        # allow up to 40. Open the requested transaction rather than sending the
        # report name as a transaction command.
        command.extend(["-type=Transaction", f"-command={normalized_transaction}"])
    subprocess.Popen(command)
    return (
        f"Opened SAP GUI for {sid}, client {client}, at {normalized_transaction} "
        f"for report {normalized_report}."
        if normalized_report
        else f"Opened SAP GUI for {sid}, client {client}."
    )


def render_sap_report_launcher(
    config: dict[str, Any],
    title: str,
    default_report: str,
    description: str,
    key_prefix: str,
    client_options: tuple[str, ...] = SAP_CLIENTS,
    report_options: dict[str, str] | None = None,
) -> None:
    """Render one SAP GUI report launcher (system, client, report, button)."""
    st.header(title)
    st.caption(description)
    systems = list(available_sap_systems(config))
    selected_sid = st.session_state.get("selected_sid", "")
    sid_col, client_col, report_col = st.columns([1, 1, 2])
    with sid_col:
        sid = st.selectbox(
            "SAP system", systems,
            index=systems.index(selected_sid) if selected_sid in systems else 0,
            key=f"{key_prefix}_system_{selected_sid}",
        )
    with client_col:
        client = st.selectbox("Client", list(client_options), key=f"{key_prefix}_client")
    with report_col:
        if report_options:
            report_label = st.selectbox(
                "System type",
                list(report_options),
                key=f"{key_prefix}_report_option",
            )
            report = report_options[report_label]
            st.caption(f"SAP report: `{report}`")
        else:
            report = st.text_input(
                "SAP report",
                value=default_report,
                key=f"{key_prefix}_report",
            )

    if st.button("Open in SAP GUI", type="primary", key=f"{key_prefix}_open"):
        try:
            with st.spinner("Opening SAP GUI..."):
                message = launch_sap_report(config, sid, client, report)
            st.success(message)
            st.info(
                "Complete the normal SAP GUI logon. In SA38, enter the report name "
                "below and verify its selection screen before executing it."
            )
            st.code(report.strip().upper() or default_report, language="text")
        except (OSError, ValueError, RuntimeError) as exc:
            st.error(str(exc))


def render_script_parameter_input(
    parameter: ScriptParameterDefinition,
    default: Any,
    widget_key: str,
) -> Any:
    """Render the widget matching a parameter's type and return its value."""
    common_options = {
        "key": widget_key,
        "help": parameter.help_text or None,
    }
    if parameter.kind == "number":
        value = default if isinstance(default, (int, float)) else 0
        return st.number_input(parameter.label, value=value, **common_options)
    if parameter.kind == "select":
        value = str(default)
        if value not in parameter.options:
            value = parameter.options[0]
        return st.selectbox(
            parameter.label,
            options=parameter.options,
            index=parameter.options.index(value),
            **common_options,
        )
    if parameter.kind == "checkbox":
        return st.checkbox(parameter.label, value=bool(default), **common_options)

    input_type = "password" if parameter.kind == "password" else "default"
    return st.text_input(
        parameter.label,
        value=str(default),
        type=input_type,
        **common_options,
    )


def render_existing_os_automations(
    config: dict[str, Any],
    scripts: list[ScriptDefinition],
    title: str,
    description: str,
    manual_guides: dict[str, dict[str, Any]] | None = None,
) -> None:
    """Render the allowlisted OS automations with their run forms.

    Some scripts require confirmed manual steps first (license download,
    RZ10 profile work); their Run buttons stay disabled until the
    matching guides are checked off.
    """
    with st.container(border=True):
        st.header(title)
        st.caption(description)

        if not scripts:
            st.info("No matching automation scripts are configured.")
            return

        st.caption(f"{len(scripts)} allowlisted script(s) available for this section.")
        selected_sid = str(st.session_state.get("selected_sid", "")).upper()
        backup_defaults = config.get("hana_backup_defaults", {})
        selected_backup_defaults = (
            backup_defaults.get(selected_sid, {})
            if isinstance(backup_defaults, dict)
            else {}
        )

        manual_guides = manual_guides or {}
        manual_before = {
            "license_and_sgen_helper": (
                "run_sgen",
                "sap_license_download",
            ),
            "profiles_1_3_5": (
                "rz10_import_profile",
                "rz10_delete_old_profiles",
            ),
        }
        script_order = {
            "hana_1_1_1_2": 0,
            "license_and_sgen_helper": 1,
            "profiles_1_3_5": 2,
        }
        completion: dict[str, bool] = {}

        for script in sorted(
            scripts, key=lambda item: script_order.get(item.script_id, 100)
        ):
            for guide_id in manual_before.get(script.script_id, ()):
                guide = manual_guides.get(guide_id)
                if guide:
                    completion[guide_id] = render_manual_guide(
                        guide, key_prefix=guide_id
                    )
                else:
                    completion[guide_id] = False
                    st.error(f"Manual guide is not configured: {guide_id}")

            prerequisite_complete = True
            if script.script_id == "license_and_sgen_helper":
                prerequisite_complete = completion.get(
                    "sap_license_download", False
                )
            elif script.script_id == "profiles_1_3_5":
                prerequisite_complete = completion.get(
                    "rz10_import_profile", False
                ) and completion.get("rz10_delete_old_profiles", False)

            with st.container(border=True):
                st.subheader(script.label)
                st.write(script.description or "No description provided.")
                st.code(script.path, language="bash")
                st.caption("Runs with SSH on the remote server.")
                if script.script_id == "hana_backup_setup":
                    if selected_sid:
                        st.info(
                            f"HANA backup defaults for selected SAP system {selected_sid}: "
                            "only configured values are prefilled; review all values before running."
                        )
                    st.info(
                        "The UCC backup script already resides on the remote server. "
                        "Streamlit executes it there over SSH and leaves the remaining "
                        "backup steps to the manual guide."
                    )
                    st.warning(
                        "The automated run uses the script's default TSM node password. "
                        "If the node has a different current password, "
                        "run the script manually because passing that password with "
                        "--pass would expose it in the remote process arguments."
                    )

                if (
                    script.script_id != "hana_backup_setup"
                    and bool(config.get("features", {}).get("allow_script_copy", False))
                    and st.button(
                        "Copy this script to the remote server",
                        key=f"copy_{script.script_id}",
                        use_container_width=True,
                    )
                ):
                    with st.spinner(f"Copying {script.label} to the remote server..."):
                        transfer_result = copy_scripts_to_server(config, [script])
                    render_transfer_result(transfer_result)

                with st.form(key=f"form_{script.script_id}"):
                    parameter_values: dict[str, Any] = {}

                    if script.parameters:
                        st.markdown("**Parameters**")

                    for parameter in script.parameters:
                        widget_key = f"param_{script.script_id}_{parameter.name}"
                        effective_default = parameter.default

                        if (
                            script.script_id == "hana_backup_setup"
                            and parameter.name in selected_backup_defaults
                        ):
                            effective_default = selected_backup_defaults[parameter.name]

                        parameter_values[parameter.name] = (
                            render_script_parameter_input(
                                parameter,
                                effective_default,
                                widget_key,
                            )
                        )

                    submit_run = st.form_submit_button(
                        "Run",
                        type="primary",
                        disabled=not prerequisite_complete,
                    )

                if submit_run:
                    try:
                        arguments = build_script_arguments(script, parameter_values)
                    except ValueError as exc:
                        st.error(str(exc))
                        continue

                    with st.spinner(f"Running {script.label}..."):
                        secret_values = [
                            str(parameter_values[p.name])
                            for p in script.parameters
                            if p.kind == "password" and str(parameter_values[p.name]).strip()
                        ]
                        result = run_script(
                            config, script, arguments, secret_input="\n".join(secret_values)
                        )
                    render_result(result)


def render_sap_gui_launcher(config: dict[str, Any]) -> None:
    """Render a multi-system SAP GUI launcher with dynamic server routing."""
    if not config.get("sap_gui"):
        return

    st.sidebar.markdown("---")
    st.sidebar.header("Select SAP system")
    st.sidebar.caption("Select target system:")

    systems = available_sap_systems(config)
    sids = list(systems)
    sid_cols = st.sidebar.columns(min(len(sids), 4))

    if "selected_sid" not in st.session_state or st.session_state["selected_sid"] not in systems:
        st.session_state["selected_sid"] = sids[0]

    for i, sid in enumerate(sids):
        with sid_cols[i % len(sid_cols)]:
            button_type = (
                "primary"
                if st.session_state["selected_sid"] == sid
                else "secondary"
            )
            if st.button(
                sid,
                type=button_type,
                use_container_width=True,
                key=f"btn_sys_{sid}",
            ):
                select_sap_system(config, sid)
                st.rerun()

    active_sid = st.session_state["selected_sid"]
    st.sidebar.caption(f"**Routing to:** `{systems[active_sid]}`")
    st.sidebar.caption("Launch client:")
    client_cols = st.sidebar.columns(3)

    def launch_sap(client: str) -> None:
        try:
            message = launch_sap_report(config, active_sid, client, "")
            st.sidebar.success(message)
        except (OSError, ValueError, RuntimeError) as exc:
            st.sidebar.error(str(exc))

    for column, client in zip(client_cols, SAP_CLIENTS):
        with column:
            if st.button(
                client,
                key=f"btn_client_{client}",
                use_container_width=True,
            ):
                launch_sap(client)

    if bool(config.get("features", {}).get("allow_session_system_addition", False)):
        with st.sidebar.expander("Add system"):
            st.caption("Added systems are available for the current browser session.")
            with st.form("add_sap_system_form"):
                new_sid = st.text_input("System ID", placeholder="Z34")
                new_host = st.text_input("Application server", placeholder="z34lp1.example.org")
                add_system = st.form_submit_button("Add system")
            if add_system:
                try:
                    add_sap_system(new_sid, new_host)
                    select_sap_system(config, new_sid)
                    st.rerun()
                except ValueError as exc:
                    st.error(str(exc))


def render_abapgit_import_guide(config: dict[str, Any]) -> None:
    """Render the abapGit bootstrap guide and an SE38 launcher for it."""
    st.header("Import ABAP code into a new SAP system")
    with st.expander("Install abapGit in a fresh SAP system first", expanded=True):
        st.markdown(
            """
1. Log in to the work client with a user who is allowed to create and activate development objects.
2. Open `SE38`, enter `ZABAPGIT_STANDALONE`, and choose **Create**. This is the standard name for the bootstrap report.
3. On the **Program attributes** screen shown in the SAP GUI, enter or select the following values:

   | Field | Value |
   | --- | --- |
   | **Title** | `abapGit standalone` (or `ABAPGIT`) |
   | **Original language** | `DE`, or your system's original development language |
   | **Type** | **Executable program** (`Ausführbares Programm`) |
   | **Status** | **Unclassified** (`Unklassifiziert`) |
   | **ABAP language version** | **Standard ABAP** |
   | **Fixed point arithmetic** | Leave selected |

   Leave **Authorization group**, **Application**, **Logical database**, and **Selection screen** empty. Leave **Editor lock** and **Start using variant** unselected. None of these fields are required for the abapGit standalone report.
4. Choose **Save**. At the package prompt, assign the bootstrap report to a local `$` package such as `$ABAPGIT`; it normally does not need a transport request. Do not use an SAP standard package.
5. Open the report in change mode and upload the standalone source code offered below via **Utilities → More Utilities → Upload/Download → Upload**, or paste it directly.
6. Activate the report. To execute it, use `SA38`, enter `ZABAPGIT_STANDALONE`, and choose **Execute**. `SE38` is used to create and maintain the report; `SA38` is used to run it.
7. In abapGit, choose **New Offline**, create a repository in a separate package of your own such as `ZS4PI`, import the generated project ZIP, and choose **Pull zip**. Keep this project package separate from the package that contains the standalone bootstrap report.
8. **Pull zip** automatically activates the imported objects in the correct order. Confirm the activation prompt if it appears.
            """
        )
        if ABAPGIT_STANDALONE_FILE.is_file():
            standalone_size_mb = ABAPGIT_STANDALONE_FILE.stat().st_size / (1024 * 1024)
            st.download_button(
                "Download abapGit standalone source code",
                data=ABAPGIT_STANDALONE_FILE.read_bytes(),
                file_name="zabapgit_standalone.prog.abap",
                mime="text/plain",
            )
            show_source = st.checkbox(
                f"Show {standalone_size_mb:.1f} MB of source code in the browser",
                value=False,
                help="Enable this only if you want to copy the source code directly from the browser.",
            )
            if show_source:
                st.code(
                    ABAPGIT_STANDALONE_FILE.read_text(encoding="utf-8"),
                    language="abap",
                )
        else:
            st.warning("The bundled abapGit standalone source code is missing.")
    st.info(
        "Do not import the ZIP into an SAP standard package. Use your own Z/Y package "
        "and a transport request if your system landscape requires it."
    )
    st.divider()
    st.subheader("Open the selected system in SE38")
    systems = list(available_sap_systems(config))
    selected_sid = st.session_state.get("selected_sid", "")
    sid = selected_sid if selected_sid in systems else systems[0]
    client = st.selectbox(
        "SAP client for abapGit",
        SAP_CLIENTS,
        index=0,
        key="abapgit_se38_client",
    )
    st.caption(
        f"Opens {sid}, client {client}, in transaction SE38. "
        "After logging on, enter `ZABAPGIT_STANDALONE` and choose Create."
    )
    if st.button("Open selected system in SE38", type="primary", key="abapgit_se38_open"):
        try:
            with st.spinner("Opening SAP GUI..."):
                message = launch_sap_report(
                    config, sid, client, "ZABAPGIT_STANDALONE", transaction="SE38"
                )
            st.success(message)
            st.info(
                "Complete the SAP GUI logon, then enter `ZABAPGIT_STANDALONE` in SE38 and choose Create. "
                "Use SA38 later when you want to execute the activated report."
            )
        except (OSError, ValueError, RuntimeError) as exc:
            st.error(str(exc))


def main() -> None:
    """Load the configuration and compose the dashboard page."""
    ui_text = load_ui_text()
    st.set_page_config(page_title=ui_text["page"]["title"], page_icon="🛠️", layout="wide")
    st.title(ui_text["page"]["title"])
    st.caption(ui_text["page"]["caption"])

    try:
        config = load_config()
        scripts = load_scripts(config)
        manual_guides = load_manual_guides()
    except Exception as exc:
        st.error(f"Configuration error: {exc}")
        st.stop()

    with st.sidebar:
        st.header("SAP navigation")
        st.caption("Select a system once; the same selection is used by the SAP GUI report launchers.")
        render_sap_gui_launcher(config)

        st.markdown("---")
        st.header("SSH connection")
        st.caption("SSH connection settings are loaded from Streamlit secrets.")
        st.write(f"SSH port: `{config.get('ssh_port', 22)}`")

    pre_transport_scripts = [
        script for script in scripts if script.script_id != "hana_backup_setup"
    ]
    backup_scripts = [
        script for script in scripts if script.script_id == "hana_backup_setup"
    ]
    render_abapgit_import_guide(config)
    st.markdown("---")
    render_existing_os_automations(
        config,
        pre_transport_scripts,
        "Existing automations before transport import",
        "HANA, profile, and license/SGEN steps from the earlier control panel.",
        manual_guides=manual_guides,
    )
    st.markdown("---")
    render_wp2_transport_system()
    st.markdown("---")
    render_post_transport_guide(config, backup_scripts)


if __name__ == "__main__":
    main()
