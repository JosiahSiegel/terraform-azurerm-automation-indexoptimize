# terraform-azurerm-automation-indexoptimize

> Azure Automation Account that runs Ola Hallengren's `IndexOptimize` against
> Azure SQL Database via managed identity, **installs Ola's procs ephemerally
> per run, then drops them** — leaving target databases with zero leftover
> maintenance objects.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

## Why this module exists

Most Ola Hallengren maintenance setups install `dbo.IndexOptimize`,
`dbo.CommandExecute`, and `dbo.CommandLog` into every target database
permanently. That's fine, but it leaves persistent objects in databases that
otherwise have nothing to do with maintenance, and it pins everyone to whatever
Ola version was installed manually months or years ago.

This module takes a different approach:

1. **Per-run install.** A weekly Azure Automation runbook connects to the
   target Azure SQL Database via the Automation Account's managed identity,
   runs `CREATE OR ALTER PROCEDURE dbo.IndexOptimize` and `dbo.CommandExecute`
   from a vendored, version-pinned copy of Ola's source bundled inside the
   runbook itself.
2. **Sentinel-tagged.** Each installed proc is tagged with extended property
   `ephemeral_runbook_install = '1'`. This is what lets the cleanup phase
   safely cohabit with manual Ola installs — it only drops procs *we* put
   there.
3. **Run.** `EXECUTE dbo.IndexOptimize @Databases = 'USER_DATABASES', ...`
   with sensible defaults (online rebuild, 2-hour cap, no log table).
4. **Cleanup in `finally`.** Sentinel-gated `DROP PROCEDURE`. Even if the run
   crashes, the next scheduled fire's opportunistic startup cleanup self-heals.

## Headline features

- **Zero crumbs.** Target databases get nothing left behind.
- **Managed identity auth.** No SQL credentials, no Key Vault secrets, no
  password rotation. Connection string uses
  `Authentication=Active Directory Managed Identity;Encrypt=Strict`.
- **Cohabits with manual Ola installs.** If your DBA already manages Ola,
  the runbook detects untagged procs and uses them as-is, never dropping
  someone else's work.
- **Crash-recovery built in.** Opportunistic startup cleanup drops orphaned
  sentinel-tagged procs from a prior failed run.
- **Multi-DB, multi-server.** One Automation Account drives staggered weekly
  schedules across as many target databases as you want.
- **Optional alerting submodule.** `modules/failure-alert/` wires a Log
  Analytics scheduled query alert + action group to a workspace, with a
  greenfield-LAW-safe KQL query (uses a `datatable` stub to bind schema
  before the dedicated tables exist).

## Prerequisites

- Azure subscription with the `Microsoft.Automation` resource provider
  registered.
- Azure SQL Database servers with **Microsoft Entra (Azure AD) admin**
  configured (the module's MI authenticates against this).
- Terraform `>= 1.5.0`.
- AzureRM provider `>= 4.0, < 5.0`.

## Quick start

```hcl
resource "azurerm_resource_group" "automation" {
  name     = "rg-automation-prod"
  location = "eastus"
}

module "indexoptimize" {
  source  = "JosiahSiegel/automation-indexoptimize/azurerm"
  version = "~> 1.0"

  name                = "myorg-prod-indexopt-auto"
  location            = azurerm_resource_group.automation.location
  resource_group_name = azurerm_resource_group.automation.name

  enable_index_optimize = true

  index_optimize_targets = {
    "salesdb-weekly" = {
      sql_server = "sqlsrv-prod.database.windows.net"
      database   = "Sales"
      week_days  = ["Saturday"]
      start_time = "2026-06-06T03:00:00-04:00"
    }
    "reportingdb-weekly" = {
      sql_server = "sqlsrv-prod.database.windows.net"
      database   = "Reporting"
      week_days  = ["Sunday"]
      start_time = "2026-06-07T03:00:00-04:00"
    }
  }

  tags = {
    Environment = "Prod"
    ManagedBy   = "Terraform"
  }
}
```

After `terraform apply`, run the following on **each target database** as
the Entra admin (one-time setup):

```sql
CREATE USER [myorg-prod-indexopt-auto] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [myorg-prod-indexopt-auto];
```

The principal name must match the Automation Account's resource name exactly.
If you ever recreate the Automation Account, drop and recreate the SQL user
to refresh the AAD object id binding.

A 5-line manual smoke test in the Azure portal — **Automation Account →
Runbooks → IndexOptimize → Start** with `sqlserver`/`database` parameters —
should produce job output ending in `IndexOptimize completed successfully.`
and `Cleanup: dropping sentinel-tagged procs we installed this run.` Then
verify zero leftovers with:

```sql
SELECT name FROM sys.objects WHERE type = 'P' AND name IN ('IndexOptimize','CommandExecute');
-- (no rows)
```

## With failure alerting

```hcl
module "indexoptimize_alerts" {
  source  = "JosiahSiegel/automation-indexoptimize/azurerm//modules/failure-alert"
  version = "~> 1.0"

  automation_account_name = module.indexoptimize.name
  law_id                  = azurerm_log_analytics_workspace.shared.id
  resource_group_name     = azurerm_resource_group.automation.name
  location                = azurerm_resource_group.automation.location

  action_group_name       = "ag-indexopt-failures"
  action_group_short_name = "idxoptFail"
  alert_name              = "alert-indexopt-failures"

  email_receivers = [
    { name = "owning-team", email_address = "dba-oncall@example.com" }
  ]

  tags = {
    Environment = "Prod"
    ManagedBy   = "Terraform"
  }
}
```

You'll also need a diagnostic setting on the Automation Account shipping
`JobLogs`, `JobStreams`, `DscNodeStatus`, `AuditEvent` to the same Log
Analytics workspace with `log_analytics_destination_type = "Dedicated"`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | n/a | Automation Account name (6-50 chars, starts with letter, alphanumeric + hyphens). |
| `location` | `string` | n/a | Azure region. |
| `resource_group_name` | `string` | n/a | Existing RG. |
| `tags` | `map(string)` | `{}` | Tags applied to all created resources. |
| `enable_index_optimize` | `bool` | `false` | If true, create the built-in IndexOptimize runbook + auto-import the SqlServer module into the PS 7.x slot. |
| `index_optimize_targets` | `map(object)` | `{}` | Per-target schedules. See [target shape](#target-shape). |
| `index_optimize_log_verbose` | `bool` | `false` | Verbose logging on the IndexOptimize runbook. |
| `index_optimize_log_progress` | `bool` | `false` | Progress logging on the IndexOptimize runbook. |
| `schedules` | `map(object)` | `{}` | Caller-supplied schedules; merged with derived schedules from `index_optimize_targets`. |
| `job_schedules` | `map(object)` | `{}` | Caller-supplied job schedules; merged with derived ones. |
| `runbooks` | `map(object)` | `{}` | Custom runbooks (PowerShell, PowerShellWorkflow, Python, etc). |
| `automation_modules` | `map(string)` | `{}` | PS 5.1 modules (URI per name). |
| `powershell72_modules` | `map(string)` | `{}` | Caller-supplied PS 7.x modules. |
| `connection_types` | `map(map(string))` | `{}` | Custom connection types. |
| `service_principal_connections` | `map(object)` | `{}` | SP connection definitions. |
| `certificates` | `map(object)` | `{}` | Certificate assets. |
| `teams_webhook_url` | `string` (sensitive) | `""` | If non-empty, deploys a Teams notification webhook. |
| `teams_webhook_expiry` | `string` | `"2030-12-31T00:00:00Z"` | Teams webhook expiry. |

### Target shape

```hcl
index_optimize_targets = {
  "<key>" = {
    sql_server  = string  # FQDN, e.g. "myserver.database.windows.net"
    database    = string  # database name (case-sensitive)
    week_days   = list(string)  # ["Sunday"], ["Saturday", "Sunday"], etc.
    start_time  = string  # ISO 8601 with offset, e.g. "2026-06-06T03:00:00-04:00"
    timezone    = optional(string, "America/New_York")
    description = optional(string, "")
  }
}
```

Each entry produces a weekly `azurerm_automation_schedule` with key
`indexoptimize-<key>` and a matching `azurerm_automation_job_schedule` bound
to the IndexOptimize runbook.

## Outputs

| Name | Description |
|---|---|
| `id` | Automation Account resource ID. |
| `name` | Automation Account name. |
| `identity` | Identity block (principal_id, tenant_id). |
| `index_optimize_runbook_name` | Runbook name (or `null` if disabled). |
| `runbooks` | `{id, name}` per custom runbook. |
| `schedules` | `{id, name}` per schedule. |
| `job_schedules` | `{id}` per job schedule. |
| `certificates` | `{id, name}` per certificate. |
| `service_principal_connections` | `{id, name, application_id}` per connection (sensitive). |
| `teams_webhook_uri` | Teams webhook URI (sensitive, `null` if disabled). |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Azure Automation Account (SystemAssigned MI)                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  PS 7.x Module Slot                                        │  │
│  │   • SqlServer 22.3.0 (auto-imported by enable_index_*)    │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  IndexOptimize runbook (PowerShell72)                      │  │
│  │   1. Import-Module SqlServer  (loads Microsoft.Data.SqlClient) │
│  │   2. Open SqlConnection with                               │  │
│  │      Authentication=Active Directory Managed Identity      │  │
│  │   3. Phase 1: opportunistic sentinel-orphan cleanup        │  │
│  │   4. Phase 2: ownership detection (ours / theirs / absent) │  │
│  │   5. Phase 3: install (CREATE OR ALTER + sentinel tag)     │  │
│  │   6. Phase 4: EXECUTE dbo.IndexOptimize ...                │  │
│  │   7. finally: sentinel-gated DROP PROCEDURE                │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Schedules (one per target, weekly, staggered)            │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │ MI auth + AAD token
                             ▼
                ┌────────────────────────────┐
                │  Azure SQL Database         │
                │   per-DB principal:         │
                │     CREATE USER ... FROM    │
                │     EXTERNAL PROVIDER       │
                │   db_owner                  │
                └────────────────────────────┘
```

## Hard-won gotchas

These are documented in source comments but worth highlighting up front:

1. **`SqlServer 22.3.0` is the pinned PS 7.2 version. Don't bump.**
   Versions 22.4.0+ are compiled against `.NETCoreApp v8.0`; the Azure
   Automation PS 7.2 runtime ships .NET 6 and fails with
   `Could not load file or assembly 'System.Runtime, Version=8.0.0.0'`.
   See [microsoft/SQLServerPSModule#111](https://github.com/microsoft/SQLServerPSModule/issues/111).

2. **Don't add `lifecycle { ignore_changes = [module_link] }`** to the
   `azurerm_automation_powershell72_module` resource. It silently masks URI
   bumps and locks the slot on whatever first imported. Use
   `terraform apply -replace=...` to push version changes.

3. **Failure-alert KQL needs a `datatable` stub** when the LAW is greenfield.
   `AutomationJobStreams` and `AutomationJobLogs` aren't pre-registered until
   first row ingests; without the stub, alert creation fails with
   "Operator source expression should be table or column" (SEM0104).
   The submodule handles this for you.

4. **Job schedule parameter keys must be lowercase.** Azure Automation
   lowercases PowerShell parameter names. The module passes `sqlserver` and
   `database` (not `SqlServer` / `Database`); the runbook's PS parameter
   binding is case-insensitive on the receive side.

5. **MI principal recreate.** If you ever recreate the Automation Account,
   the new MI gets a new AAD object id but the same display name. The
   existing `CREATE USER ... FROM EXTERNAL PROVIDER` SQL principal binds to
   the *old* object id and breaks. Fix: `DROP USER ...; CREATE USER ... FROM
   EXTERNAL PROVIDER; ALTER ROLE db_owner ADD MEMBER ...` on every target DB.

6. **Schedule `start_time` is `ignore_changes`d.** The provider has a
   timezone+offset round-trip drift bug; we hide it. To actually update a
   schedule's start time, taint or `-replace=` it.

## Onboarding a new database to an existing deployment

1. Append an entry to `index_optimize_targets`:
   ```hcl
   "newdb-key" = {
     sql_server = "myserver.database.windows.net"
     database   = "MyNewDatabase"
     week_days  = ["Friday"]
     start_time = "2026-07-03T03:00:00-04:00"
   }
   ```
2. `terraform apply`.
3. As Entra admin, run on the new database:
   ```sql
   CREATE USER [<your-automation-account-name>] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_owner ADD MEMBER [<your-automation-account-name>];
   ```
4. Wait for the schedule to fire, or manually trigger the runbook with the
   new sqlserver/database parameters.

## License

Apache 2.0. See [LICENSE](LICENSE).

The bundled Ola Hallengren SQL Server Maintenance Solution
(`scripts/ola/MaintenanceSolution.sql` and the embedded `CommandExecute` /
`IndexOptimize` here-strings inside `scripts/IndexOptimize.ps1`) is
distributed under its own MIT license — see
[scripts/ola/LICENSE.md](scripts/ola/LICENSE.md).

## Contributing

Issues and PRs welcome. The most-likely useful contributions:

- Refresh the embedded Ola source when a new version drops (procedure in
  [scripts/ola/README.md](scripts/ola/README.md)).
- Examples for additional patterns (Bicep co-deployment, CI/CD wiring).
- Bicep / Pulumi siblings.

## Acknowledgements

- **Ola Hallengren** for the [SQL Server Maintenance Solution](https://ola.hallengren.com/).
- The Microsoft Q&A and `microsoft/SQLServerPSModule` GitHub communities for
  documenting the PS 7.2 / .NET 6 module compatibility issues that informed
  the SqlServer 22.3.0 pin.
