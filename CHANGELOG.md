# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Existing Automation Account support.** New variables `create_automation_account`,
  `existing_automation_account_name`, and `existing_automation_account_resource_group_name`
  allow the module to use an existing Automation Account instead of always creating one.
- `public_network_access_enabled` variable (default `false`) on the Automation Account.
- `log_activity_trace_level` variable for the IndexOptimize runbook (default `"Trace"`).
- `providers.tf` at root declaring the `azurerm` provider.
- GitHub Actions CI workflow (`.github/workflows/ci.yml`) with `terraform-fmt`,
  `terraform-validate`, `tflint`, `checkov`, and `terraform-docs` jobs.
- `examples/failure-alert/` — complete example using the `failure-alert` submodule.
- `.claude/` added to `.gitignore`.

### Changed
- Terraform `required_version` bumped from `>= 1.5.0` to `>= 1.9.0` in root,
  `examples/minimal/`, and `modules/failure-alert/`.
- `identity` output now marked `sensitive = true`.

### Security
- Default `public_network_access_enabled = false` on new Automation Accounts.
- README warning added: `teams_webhook_url` values are stored in Terraform state
  even though the variable is `sensitive`.

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
