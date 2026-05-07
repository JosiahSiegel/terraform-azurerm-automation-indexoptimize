# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project follows
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-05-07

Initial public release.

### Added
- Azure Automation Account with SystemAssigned managed identity.
- Built-in `IndexOptimize` runbook (PowerShell 7.2) wrapping Ola Hallengren's
  stored procedures with ephemeral install + sentinel-tagged cleanup.
- Embedded Ola Hallengren source (version `2026-04-06 02:01:02`), MIT
  licensed, vendored for offline / repeatable installs.
- `index_optimize_targets` input — single map drives weekly schedules and
  job_schedules per target database.
- Auto-import of `SqlServer 22.3.0` PowerShell module into the PS 7.x slot
  when `enable_index_optimize = true` (.NET 6 compatible; do not bump to
  22.4.x — known broken on PS 7.2 runtime).
- Optional Teams notification webhook (`teams_webhook_url`).
- Pass-through inputs for caller-supplied custom runbooks, schedules,
  job_schedules, certificates, connection types, and SP connections.
- Submodule `modules/failure-alert/` — Log Analytics scheduled query alert
  + action group with greenfield-LAW-safe `datatable` stub workaround for
  the SEM0104 "Operator source expression should be table or column" error.

### Module design
- Connection auth via `Microsoft.Data.SqlClient` connection string
  (`Authentication=Active Directory Managed Identity;Encrypt=Strict`) —
  no `Az.Accounts`, no token unwrapping, no SecureString gotchas.
- `lifecycle { ignore_changes = [start_time] }` on schedules to defend
  against the AzureRM provider's timezone+offset round-trip drift bug.
- Sentinel pattern (`sp_addextendedproperty ephemeral_runbook_install = '1'`)
  ensures cleanup never drops procs from a manual Ola install.
- Opportunistic startup cleanup on every run for crash-recovery self-healing.

### Compatibility
- Terraform `>= 1.5.0`
- AzureRM provider `>= 4.0, < 5.0`
- Tested on AzureRM `4.26.0` and `4.71.0`.
