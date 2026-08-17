"""Offline unit tests for the dashboard's core logic.

Covers SSH/SCP command construction, script-argument building, catalog
validation, transport-profile validation, SAP system filtering, and the
input validation of the SAP GUI launcher. No network, SSH server, or SAP
system is required.
"""

import json
import unittest

import app


def make_config(**overrides):
    """Return a minimal valid app configuration for tests."""
    config = {
        "server": "deployuser@server.example.org",
        "ssh_key_path": "~/.ssh/test_key",
        "known_hosts_path": "~/.ssh/known_hosts",
        "ssh_port": 22,
        "connect_timeout_seconds": 10,
        "default_timeout_seconds": 300,
        "transport_config_upload": {"remote_directory": "/srv/transport"},
        "sap_gui": {
            "executable_path": "",
            "instance_number": "00",
            "systems": {"Z31": "z31lp1.example.org", "Z04": "z04lp1.example.org"},
        },
        "features": {},
        "hana_backup_defaults": {},
        "scripts": [],
    }
    config.update(overrides)
    return config


def make_script(parameters):
    """Return a ScriptDefinition with the given parameter definitions."""
    return app.load_scripts(
        {
            "default_timeout_seconds": 60,
            "scripts": [
                {
                    "id": "demo",
                    "label": "Demo",
                    "path": "/opt/postinstall/demo.sh",
                    "parameters": parameters,
                }
            ],
        }
    )[0]


class BuildRemoteCommandTests(unittest.TestCase):
    def test_quotes_arguments_against_shell_injection(self) -> None:
        command = app.build_remote_command(["/opt/x.sh", "a b", "$(rm -rf /)"])
        self.assertEqual(command, "/opt/x.sh 'a b' '$(rm -rf /)'")


class BuildSshCommandTests(unittest.TestCase):
    def test_uses_strict_host_key_checking_and_batch_mode(self) -> None:
        command = app.build_ssh_command(make_config(), "/opt/x.sh")
        self.assertEqual(command[0], "ssh")
        self.assertIn("BatchMode=yes", command)
        self.assertIn("StrictHostKeyChecking=yes", command)
        self.assertEqual(command[-2:], ["deployuser@server.example.org", "/opt/x.sh"])

    def test_uses_configured_port(self) -> None:
        command = app.build_ssh_command(make_config(ssh_port=2222), "/opt/x.sh")
        self.assertIn("2222", command)


class BuildScpCommandTests(unittest.TestCase):
    def test_places_sources_before_destination(self) -> None:
        command = app.build_scp_command(
            make_config(), ["/local/a.sh", "/local/b.sh"], "user@host:/tmp/"
        )
        self.assertEqual(command[0], "scp")
        self.assertIn("StrictHostKeyChecking=yes", command)
        self.assertEqual(command[-3:], ["/local/a.sh", "/local/b.sh", "user@host:/tmp/"])


class BuildScriptArgumentsTests(unittest.TestCase):
    def test_flag_parameters_are_emitted_with_values(self) -> None:
        script = make_script(
            [{"name": "sid", "type": "text", "flag": "--sid", "default": ""}]
        )
        arguments = app.build_script_arguments(script, {"sid": "S31"})
        self.assertEqual(arguments, ["--sid", "S31"])

    def test_checkbox_flag_is_emitted_only_when_checked(self) -> None:
        script = make_script(
            [{"name": "dry", "type": "checkbox", "flag": "--dry-run"}]
        )
        self.assertEqual(app.build_script_arguments(script, {"dry": True}), ["--dry-run"])
        self.assertEqual(app.build_script_arguments(script, {"dry": False}), [])

    def test_missing_required_value_raises(self) -> None:
        script = make_script(
            [{"name": "sid", "type": "text", "flag": "--sid", "required": True}]
        )
        with self.assertRaises(ValueError):
            app.build_script_arguments(script, {"sid": "  "})

    def test_optional_empty_value_is_skipped(self) -> None:
        script = make_script(
            [{"name": "sid", "type": "text", "flag": "--sid", "default": ""}]
        )
        self.assertEqual(app.build_script_arguments(script, {"sid": ""}), [])

    def test_password_values_never_appear_in_arguments(self) -> None:
        script = make_script(
            [
                {"name": "sid", "type": "text", "flag": "--sid", "default": ""},
                {"name": "secret", "type": "password", "flag": "--pass"},
            ]
        )
        arguments = app.build_script_arguments(
            script, {"sid": "S31", "secret": "hunter2"}
        )
        self.assertEqual(arguments, ["--sid", "S31"])
        self.assertNotIn("hunter2", arguments)


class LoadScriptsTests(unittest.TestCase):
    def test_rejects_relative_script_path(self) -> None:
        with self.assertRaises(ValueError):
            app.load_scripts(
                {"scripts": [{"id": "x", "label": "X", "path": "relative/x.sh"}]}
            )

    def test_rejects_unknown_parameter_type(self) -> None:
        with self.assertRaises(ValueError):
            make_script([{"name": "p", "type": "file"}])

    def test_rejects_select_without_options(self) -> None:
        with self.assertRaises(ValueError):
            make_script([{"name": "p", "type": "select"}])

    def test_applies_default_timeout(self) -> None:
        script = make_script([])
        self.assertEqual(script.timeout_seconds, 60)


class ValidateTransportConfigTests(unittest.TestCase):
    def test_accepts_valid_payload(self) -> None:
        payload = json.dumps({"transports": ["T1", "T2"]}).encode("utf-8")
        parsed, count = app.validate_transport_config(payload)
        self.assertEqual(count, 2)
        self.assertEqual(parsed["transports"], ["T1", "T2"])

    def test_rejects_oversized_file(self) -> None:
        with self.assertRaises(ValueError):
            app.validate_transport_config(b"0" * (2 * 1024 * 1024 + 1))

    def test_rejects_invalid_json(self) -> None:
        with self.assertRaises(ValueError):
            app.validate_transport_config(b"not json")

    def test_rejects_missing_or_empty_transports(self) -> None:
        with self.assertRaises(ValueError):
            app.validate_transport_config(b"{}")
        with self.assertRaises(ValueError):
            app.validate_transport_config(b'{"transports": []}')


class UploadTransportConfigValidationTests(unittest.TestCase):
    def test_rejects_unsafe_remote_directory(self) -> None:
        for bad_directory in ("relative/path", "/srv/../etc", "/srv/tra nsport", ""):
            config = make_config(
                transport_config_upload={"remote_directory": bad_directory}
            )
            with self.assertRaises(ValueError):
                app.upload_transport_config(config, "Z31", b"{}")

    def test_rejects_invalid_sid(self) -> None:
        with self.assertRaises(ValueError):
            app.upload_transport_config(make_config(), "z3", b"{}")


class AvailableSapSystemsTests(unittest.TestCase):
    def test_returns_sorted_valid_systems(self) -> None:
        systems = app.available_sap_systems(make_config())
        self.assertEqual(
            systems,
            {"Z04": "z04lp1.example.org", "Z31": "z31lp1.example.org"},
        )
        self.assertEqual(list(systems), ["Z04", "Z31"])

    def test_drops_invalid_entries(self) -> None:
        config = make_config(
            sap_gui={
                "systems": {
                    "Z31": "z31lp1.example.org",
                    "TOOLONG": "host",
                    "Z32": "bad host name",
                }
            }
        )
        self.assertEqual(list(app.available_sap_systems(config)), ["Z31"])

    def test_raises_when_no_system_is_configured(self) -> None:
        with self.assertRaises(ValueError):
            app.available_sap_systems(make_config(sap_gui={"systems": {}}))


class LaunchSapReportValidationTests(unittest.TestCase):
    def test_rejects_invalid_report_name(self) -> None:
        with self.assertRaises(ValueError):
            app.launch_sap_report(make_config(), "Z31", "000", "bad-report!")

    def test_rejects_invalid_client(self) -> None:
        with self.assertRaises(ValueError):
            app.launch_sap_report(make_config(), "Z31", "00", "ZREPORT")

    def test_rejects_invalid_transaction(self) -> None:
        with self.assertRaises(ValueError):
            app.launch_sap_report(
                make_config(), "Z31", "000", "ZREPORT", transaction="sa 38"
            )

    def test_missing_sap_gui_executable_raises_runtime_error(self) -> None:
        with self.assertRaises(RuntimeError):
            app.launch_sap_report(make_config(), "Z31", "000", "ZREPORT")


class ResolveAssetPathTests(unittest.TestCase):
    def test_rejects_path_traversal(self) -> None:
        with self.assertRaises(ValueError):
            app.resolve_asset_path("../secrets.toml")

    def test_resolves_inside_assets_directory(self) -> None:
        resolved = app.resolve_asset_path("profile/rz10_1.png")
        self.assertTrue(str(resolved).startswith(str(app.ASSETS_DIR.resolve())))


if __name__ == "__main__":
    unittest.main()
