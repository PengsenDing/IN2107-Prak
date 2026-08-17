# Post-Installation Cockpit for SAP UCC

**A guided automation dashboard that turns a 30+ page manual SAP S/4HANA setup
procedure into one controlled workflow — saving an estimated 5–9 operator
hours per system.**

## What this project does

The SAP University Competence Center (UCC) München at TUM provisions more than
20 SAP S/4HANA enterprise systems every year. After the technical
installation, each system still needs hours of configuration — licenses,
security stores, users, background jobs, transports, backups — performed by
hand from a 30+ page wiki across four different tools (Linux command line,
SAP HANA Studio, SAP GUI, SAP for Me).

The Post-Installation Cockpit replaces that fragmented process with a single
local web dashboard that:

- **guides** the operator through every step in the correct order, with
  embedded instructions and screenshots,
- **automates** the repeatable steps by running a fixed allowlist of scripts
  on the SAP server over SSH, with typed input forms and dry-run previews,
- **launches** SAP GUI directly into the right system, client, and report for
  the steps that must stay interactive,
- **shows the evidence** for every run — exit code, output, and errors — in
  the same place.

High-risk steps stay manual **by design**: the operator keeps control and
accountability, while the cockpit removes the repetitive mechanics.

## Impact

| | |
| --- | --- |
| **81% task coverage** | 34 of the 42 post-installation subtasks automated or script-assisted |
| **5–9 hours saved per system** | modeled from the wiki workflow (9–14 h manual before, 4–5 h after) |
| **100–180 hours saved per year** | at the conservative baseline of 20 systems annually (≈ 13–23 working days) |
| **Lower error risk** | allowlisted commands, validated typed inputs, and shell-injection-safe quoting replace freehand terminal work |

The full engagement analysis — client problem, stakeholder requirements,
options considered, and adoption recommendation — is in the
**[consultancy report](docs/consultancy-report.md)**.

## Tech stack

| Layer | Technology |
| --- | --- |
| Frontend / UI | Streamlit (Python 3.12) — forms, guided steps, result panels |
| Remote execution | OpenSSH (`ssh`/`scp`) with a dedicated deploy user, key-based auth, and strict host-key verification |
| Automation logic | Bash scripts with dry-run mode; ABAP Z-reports delivered via abapGit |
| SAP integration | SAP GUI shortcut launcher (`sapshcut`); SAP/HANA CLI tools (`hdbsql`, `sapcontrol`, `saplikey`, `sappfpar`) on the server |
| Configuration | TOML secrets (untracked) + JSON script catalog / UI text / guide content |
| Quality & delivery | 30 offline unit tests (`unittest`), Docker image, pinned dependencies |

Security highlights: no free-text command execution, shell-quoted arguments,
passwords passed via stdin (never process arguments), no SAP credentials
stored, and a minimal remote footprint — the SAP server needs only OpenSSH
and the predefined scripts, no agent or web server.

## Architecture

```text
Operator notebook (Windows)
  Post-Installation Cockpit (Streamlit, this repository)
    ├─ sapshcut.exe  ──────────►  SAP GUI logon / report selection screen
    └─ ssh / scp (OpenSSH)  ───►  remote server: allowlisted scripts,
                                  transport-configuration upload

Remote server
  OpenSSH server, dedicated deploy user, scripts in fixed locations
```

The application makes **no RFC, HTTP, SOAP, or database connections to SAP**
and never collects or stores SAP credentials. SAP GUI performs the normal
interactive logon; SSH uses a dedicated key pair.

## Repository layout

```text
app.py                          Main dashboard: config loading, SSH/SCP command
                                building, SAP GUI launcher, page composition
sap_connectivity.py             SAP connectivity configuration guides (SLD, SNOTE, …)
post_transport_wiki.py          Renderer for the curated wiki export
post_transport_wiki_content.json  Curated wiki content (text, images, tables)
wp2_secstore.py                 Manual SECSTORE guide
wp2_transport_system.py         Manual transport-system setup guide
scripts_catalog.json            Allowlist of remote scripts and their parameters
manual_steps.json               Manual guides shown before automations
ui_text.json                    Page title and shared UI strings
bulk-transports-gb43.json       Default GB 4.3 transport-import profile
config.sample.toml              Template for .streamlit/secrets.toml
scripts/                        Local copies of the allowlisted shell scripts
server_examples/                Example server-side setup (users, sudoers, …)
abap/                           ABAP sources (abapGit format) for the Z-reports
images/                         Screenshots used by the manual guides
docs/                           Consultancy report (engagement context and recommendation)
tests/                          Unit tests (no network, no SAP system required)
```

## Quickstart

Prerequisites on the operator notebook:

- Python 3.12 or newer
- OpenSSH client (`ssh`, `scp` on the PATH)
- SAP GUI for Windows (only needed for the SAP GUI launcher buttons)

```bash
# 1. Create a virtual environment
python -m venv .venv
source .venv/bin/activate          # Windows PowerShell: .\.venv\Scripts\Activate.ps1

# 2. Install the dependencies
pip install -r requirements.txt

# 3. Create the local configuration (ignored by Git)
mkdir -p .streamlit
cp config.sample.toml .streamlit/secrets.toml   # PowerShell: Copy-Item config.sample.toml .streamlit\secrets.toml

# 4. Edit .streamlit/secrets.toml (see "Configuration" below)

# 5. Run the dashboard
streamlit run app.py
```

The dashboard starts on <http://localhost:8501>. It renders with the sample
values, but SSH actions and SAP GUI launches only work once the configuration
points at a real server and SAP GUI installation.

### Run with Docker (SSH features only)

```bash
docker build -t postinstall-cockpit .
docker run --rm -p 8501:8501 \
  -v "$PWD/.streamlit/secrets.toml:/app/.streamlit/secrets.toml:ro" \
  -v "$HOME/.ssh:/home/app/.ssh:ro" \
  postinstall-cockpit
```

The container includes the OpenSSH client, so the SSH runner and the transport
upload work. The **SAP GUI launcher requires a native Windows installation**
of SAP GUI and therefore does not work from inside a container; run the app
natively on the operator notebook when SAP GUI launches are needed.

## Configuration

All machine-specific settings live in `.streamlit/secrets.toml`, which is
ignored by Git. `config.sample.toml` documents every key:

| Section | Key | Meaning |
| --- | --- | --- |
| `[ssh]` | `server` | `user@host` used for all SSH/SCP actions (required) |
| | `private_key_path` | Private key for the dedicated deploy user (required) |
| | `known_hosts_path` | known_hosts file; host keys are verified **strictly** |
| | `port`, `connect_timeout_seconds` | Optional connection settings |
| `[features]` | `allow_script_copy` | Enable copying allowlisted scripts to `/tmp/` on the server |
| | `allow_session_system_addition` | Allow adding SAP systems for the browser session |
| `[transport]` | `remote_directory` | Absolute remote path for uploaded transport profiles; must be writable by the SSH user and readable by the SAP application server |
| `[sap_gui]` | `executable_path` | Path to `sapshcut.exe` from the SAP GUI installation |
| | `instance_number` | Two-digit instance number used to build the `/H/<host>/S/32<nr>` route |
| `[sap_gui.systems]` | `<SID> = "<host>"` | Approved SAP systems shown in the sidebar |
| `[hana_backup_defaults.<SID>]` | `sid`, … | Values prefilled in the HANA backup form per system |

The remote script allowlist lives in `scripts_catalog.json`. Each entry
defines the absolute remote path, a label and description, and typed
parameters (text, number, password, select, checkbox) that the dashboard
renders as form fields and forwards as command-line arguments. Password
parameters are **never** passed as arguments; they are written to the remote
script's standard input.

## SSH setup

Create a dedicated key and copy it to the server:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/postinstall_deploy_key -C "postinstall-runner"
ssh-copy-id -i ~/.ssh/postinstall_deploy_key.pub deployuser@YOUR_SERVER
```

Test the connection manually before using the dashboard:

```bash
ssh -i ~/.ssh/postinstall_deploy_key deployuser@YOUR_SERVER '/opt/postinstall/02_profiles_1_3_5.sh --help'
```

Minimal server-side setup (dedicated user, fixed script directory):

```bash
sudo useradd --create-home --shell /bin/bash deployuser
sudo mkdir -p /opt/postinstall
sudo cp scripts/*.sh /opt/postinstall/
sudo chmod 755 /opt/postinstall/*.sh
sudo chown root:root /opt/postinstall/*.sh
```

`server_examples/` contains example health-check and provisioning scripts and
a sudoers fragment for a locked-down deploy user.

## SAP GUI launcher

The launcher builds a `sapshcut.exe` command for the selected system, client,
and report. Because SAP transaction codes are limited to 20 characters while
report names may have up to 40, the launcher opens transaction `SA38` after
the interactive logon and displays the report name for the operator to enter
and execute manually. The dashboard never uses SAP GUI Scripting and never
passes SAP credentials.

Report launchers exist for the delivered Z-reports, for example
`ZBULK_TRANSPORT_IMPORT`, `ZFRONTEND_PRINT_PLAN`, `ZCLIENT_PROVISIONING`,
`Z_USER_CUSTOMIZATION`, and the welcome-text variants.

## Transport-configuration upload

For transport imports, the dashboard validates and uploads a JSON profile via
the configured SSH connection to `[transport].remote_directory`. The primary
action uploads the bundled `bulk-transports-gb43.json` (the GB 4.3 standard);
a file picker accepts custom profiles that deviate from the standard. After
the upload, the dashboard displays the remote path to enter in the
`ZBULK_TRANSPORT_IMPORT` report.

## ABAP sources

The Z-reports opened by the launchers are maintained in `abap/` in abapGit
format. To install them on a fresh system, follow the in-app guide: create
the `ZABAPGIT_STANDALONE` bootstrap report (source bundled in
`abap/vendor/`), then import the project ZIP built with
`abap/tools/build-abapgit-flat-zip.ps1` as an offline repository.

## Testing

```bash
python -m unittest discover -s tests -v
```

The tests cover command construction, parameter validation, catalog loading,
and input validation. They run offline: no SAP system, no SSH server, and no
network access are required.

## Security notes

- Keep the Streamlit app local or protect it with network restrictions; do
  not expose the UI publicly without authentication.
- `.streamlit/secrets.toml` stays outside version control; never commit
  hostnames, keys, or passwords.
- Host keys are verified strictly (`StrictHostKeyChecking=yes`); populate
  `known_hosts_path` before running SSH actions.
- The script allowlist is fixed in `scripts_catalog.json`; there is no
  free-text command execution.
- Use a dedicated SSH deploy user, not a personal admin user, and keep the
  remote scripts idempotent.
- Password-bearing script options are disabled until their interfaces accept
  secrets through standard input or a protected credential store instead of
  command-line arguments.
- Validate configuration changes in staging before production use.

## Literature (Hochschulformat)

1. Streamlit (o. J.): Streamlit Documentation. Verfuegbar unter: https://docs.streamlit.io/ (Zugriff: 10.07.2026).
2. Streamlit (o. J.): API Reference. Verfuegbar unter: https://docs.streamlit.io/develop/api-reference (Zugriff: 10.07.2026).
3. Python Software Foundation (2026): subprocess - Subprocess management. Verfuegbar unter: https://docs.python.org/3/library/subprocess.html (Zugriff: 10.07.2026).
4. OpenBSD (2026): ssh(1) - OpenSSH remote login client. Verfuegbar unter: https://man.openbsd.org/ssh (Zugriff: 10.07.2026).
5. OpenBSD (2025): scp(1) - OpenSSH secure file copy. Verfuegbar unter: https://man.openbsd.org/scp (Zugriff: 10.07.2026).
6. Ylonen, T.; Lonvick, C. (2006): The Secure Shell (SSH) Protocol Architecture (RFC 4251). Internet Engineering Task Force (IETF). Verfuegbar unter: https://datatracker.ietf.org/doc/html/rfc4251 (Zugriff: 10.07.2026).
7. OWASP Cheat Sheet Series Team (2026): OS Command Injection Defense Cheat Sheet. Verfuegbar unter: https://cheatsheetseries.owasp.org/cheatsheets/OS_Command_Injection_Defense_Cheat_Sheet.html (Zugriff: 10.07.2026).
8. OWASP Cheat Sheet Series Team (2026): File Upload Cheat Sheet. Verfuegbar unter: https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html (Zugriff: 10.07.2026).
9. National Institute of Standards and Technology (NIST) (2025): Digital Identity Guidelines: Authentication and Lifecycle Management (SP 800-63B-4). Verfuegbar unter: https://pages.nist.gov/800-63-4/sp800-63b.html (Zugriff: 10.07.2026).
