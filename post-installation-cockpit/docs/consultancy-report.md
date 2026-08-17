# Consultancy Report

**Automation of the Post-Installation Configuration of SAP S/4HANA Systems**

| | |
| --- | --- |
| Client | SAP University Competence Center (UCC) München, Technical University of Munich |
| Engagement | IN2128 practicum — Next Generation Data Center Operations for SAP Enterprise Software |
| Period | Summer Semester 2026 |
| Team | Pengsen Ding (System Provisioning Lead), Jonas Schiffels (Core Infrastructure Lead), Wenhao Hu (Integration Lead), Simon Sturhan (Project Manager) |
| Deliverable | This report, the Post-Installation Cockpit in this repository, and the final presentation |

## 1. Executive summary

The UCC provisions more than 20 SAP S/4HANA systems per year. After the technical
installation, every system requires a post-installation configuration that is
documented in a wiki workflow of more than 30 pages and executed manually across
four different tools (Linux command line, SAP HANA Studio, SAP Logon, SAP for Me).

We recommend — and deliver as a working implementation — the
**Post-Installation Cockpit**: a local Streamlit application that leads the
operator through the
post-installation procedure in wiki order and executes the repeatable steps as
allowlisted scripts over SSH, while keeping screen-dependent and high-risk steps
as explicit, documented operator tasks.

Of the 42 subtasks in the post-installation workflow, **34 (81%) are automated or
script-assisted**; 8 remain manual by design. Based on a transparent model of the
wiki workflow (not production telemetry), this removes an estimated **5–9 operator
hours per system**, or **100–180 hours per year** at the conservative 20-system
baseline — roughly 13–23 working days of basis capacity returned annually.

## 2. Client context and problem statement

An installed S/4HANA system is not an operational one. Before handover, every
system needs licenses, profiles, transport connectivity, users, jobs, RFC
destinations, clients, backup integration, and monitoring. Today this gap is
closed manually, which creates three business bottlenecks:

- **Time drain** — an estimated 9–14 hours of manual operator touch time per
  system, repeated for every installation.
- **Error risk** — the operator interprets a 30+ page wiki, switches between
  four tools, and re-enters the same values repeatedly; every context switch is
  an opportunity for deviation.
- **Scalability risk** — throughput is bound to experienced operators; the
  documented volume of 20+ systems per year cannot grow without either more
  staff or less variation per system.

## 3. Stakeholder requirements

Agreed with the client at the start of the engagement, with the guiding
principle *"if automation is harder than the manual process, it is useless"*:

| Requirement | Meaning | How the solution meets it |
| --- | --- | --- |
| **Accessible** | Easy to trigger, integrates with the existing landscape | One local web UI; the SAP server needs only OpenSSH and predefined scripts — no new platform, agent, or service |
| **Standardized** | Built on standard tools the team can read, adapt, and maintain | Python/Streamlit, Bash, OpenSSH, ABAP delivered via abapGit; no proprietary framework |
| **Transparent** | Shows exactly what changed and where it succeeded or failed | Dry-run mode, typed parameters, and per-run exit code, stdout, and stderr displayed in the UI |

## 4. Options considered

| Option | Assessment |
| --- | --- |
| **Keep the manual wiki process** (baseline) | No investment, but the time, error, and scalability problems persist and grow with volume. Rejected. |
| **Full automation platform on the SAP hosts** (e.g., agent-based configuration management) | Highest ceiling, but installs new software on every SAP host, adds a platform the team must operate, and contradicts the small-footprint requirement. Rejected for this engagement. |
| **SAP GUI scripting / screen automation** | Could cover the screen-dependent steps, but is brittle across GUI versions, hard to review, and hides actions from the operator. Rejected. |
| **RFC-based execution from the app** (pyrfc + NetWeaver RFC SDK) | Technically viable for ABAP steps and evaluated during the project, but adds SDK distribution, credential handling, and a second execution path. Deferred; ABAP steps are instead delivered as Z-reports the operator runs in SAP GUI. |
| **Guided dashboard + allowlisted SSH execution** (recommended) | Automates the deterministic OS/HANA steps, guides the rest, keeps the remote footprint at OpenSSH + scripts, and keeps every action reviewable. **Selected.** |

## 5. Recommended solution

A local Streamlit application on the operator notebook, with controlled remote
execution:

```text
Operator notebook                      Remote SAP host / LPAR
  Streamlit UI                           OpenSSH server
  script allowlist (scripts_catalog)     dedicated deploy user
  private SSH key            ──SSH/SCP─► /opt/postinstall scripts
  sapshcut.exe (SAP GUI)     ──SAP GUI─► SAP/HANA CLI tools (hdbsql,
                                         sapcontrol, saplikey, sappfpar)
```

Design principle: **only automate what can be parameterized, validated, and
safely repeated; keep human validation where the SAP workflow is
screen-dependent.** The operator keeps accountability — they choose the target
system and the approved task; the application standardizes how it runs.

Details of the implementation, configuration, and setup are in
[README.md](../README.md).

## 6. Automation boundary and coverage

The 15 top-level tasks (42 subtasks) of the post-installation workflow are
classified into three tiers:

- **Automated** — stable inputs, deterministic outcome: HANA SYSTEM password and
  allocation limit, profile parameters, user configuration in client 000,
  standard jobs, RFC groups, logical systems, month change, Fiori start screen,
  frontend-print fix, patch/transport import support, client provisioning,
  HANA backup setup (steps 1–2).
- **Assisted** — scripted preparation or validation for screen-dependent work:
  license installation (generation in SAP for Me stays manual), SGEN
  (component selection and job start are screen-flow dependent).
- **Manual by design** — judgment or landscape-wide risk: SECSTORE, RFC
  connection management, background-job rescheduling, **transport-system
  setup**, lecturer tiles, external services, and monitoring integration.
  The dashboard embeds the step-by-step guides for these so the operator never
  leaves the guided flow.

**Result: 34 of 42 subtasks (81%) are covered.** The remaining boundary is not a
gap but a safety decision: automation stays broad where repetition is safe and
ownership stays explicit where consequences are larger.

## 7. Business case

Modeled from the wiki workflow — an estimate, not production telemetry:

| Metric | Value |
| --- | --- |
| Manual operator touch per system (before) | 9–14 h |
| Remaining human effort per system (after) | 4–5 h |
| Saved per installation | **5–9 h** |
| Annual saving at the 20-system lower bound | **100–180 h (≈ 13–23 working days)** |

Not counted as savings: the intrinsic runtime of SGEN, transport distribution,
restarts, and client copies — automation reduces attendance, repeated input,
and rework; it does not make those SAP processes execute faster. Since the
actual annual installation count is above 20, the true impact is higher than
this baseline. The recovered capacity can support incident handling,
monitoring, quality assurance, and further automation.

## 8. Risks and safety decisions

| Risk | Mitigation |
| --- | --- |
| Arbitrary command execution from the UI | Fixed allowlist in `scripts_catalog.json`; no free-text shell; all arguments shell-quoted |
| Compromised or over-privileged access | Dedicated deploy user and SSH key instead of personal admin accounts; strict host-key verification |
| Destructive change applied blindly | Dry-run mode, backups, and validation before disruptive changes; execution checkboxes off by default |
| Credential exposure | No SAP credentials in the app; SSH secrets in an untracked local file; password parameters passed via stdin, never as process arguments |
| New attack surface on SAP hosts | Small remote footprint: OpenSSH plus scripts only — no Streamlit, web server, or agent installed remotely |

## 9. Adoption recommendation

1. **Pilot** the dashboard on the next scheduled S/4HANA installation alongside
   the wiki, with the wiki as fallback.
2. **Validate in staging** before production use; populate `known_hosts` and the
   approved system list centrally.
3. **Record actual times** during the pilot to replace the modeled 5–9 h saving
   with measured telemetry.
4. **Extend gradually**: move "assisted" steps toward automation only when their
   inputs prove stable across installations; revisit RFC-based execution once
   the SSH path is established in operations.
5. **Operate the allowlist as a reviewed artifact**: changes to
   `scripts_catalog.json` and the remote scripts go through the same review as
   any production change.

## 10. Open points

- The transport-system setup is delivered as a guided manual procedure in the
  dashboard. Its final shape follows the client's direction from the project
  reviews and should be re-confirmed with the client before the next
  installation cycle.
- The modeled time savings must be validated with measured pilot data
  (see §9.3).
