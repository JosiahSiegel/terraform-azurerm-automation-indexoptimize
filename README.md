# terraform-azurerm-automation-indexoptimize

> Azure Automation Account that runs Ola Hallengren's `IndexOptimize` against
> Azure SQL Database via managed identity, **installs Ola's procs ephemerally
> per run, then drops them** — leaving target databases with zero leftover
> maintenance objects.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Terraform Registry](https://img.shields.io/badge/terraform-registry-blue)](https://registry.terraform.io/modules/JosiahSiegel/automation-indexoptimize/azurerm/latest)

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
- Terraform `>= 1.9.0`.
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

## Existing Automation Account

If you already have an Automation Account and want the module to provision
runbooks, schedules, and modules into it instead of creating a new one, set
`create_automation_account = false` and provide the existing account's name
and resource group:

```hcl
module "indexoptimize" {
  source  = "JosiahSiegel/automation-indexoptimize/azurerm"
  version = "~> 1.0"

  create_automation_account = false
  existing_automation_account_name                = "my-existing-automation-account"
  existing_automation_account_resource_group_name = "rg-existing-automation"

  name                = "my-existing-automation-account"
  location            = "eastus"
  resource_group_name = "rg-existing-automation"

  enable_index_optimize = true

  index_optimize_targets = {
    "mydb-weekly" = {
      sql_server = "myserver.database.windows.net"
      database   = "MyDatabase"
      week_days  = ["Saturday"]
      start_time = "2026-06-06T03:00:00-04:00"
    }
  }

  tags = {
    Environment = "Prod"
    ManagedBy   = "Terraform"
  }
}
```

When `create_automation_account = false`, the module skips
`azurerm_automation_account` creation and looks up the existing account via
`data.azurerm_automation_account`. All runbooks, schedules, modules, and
other resources are still created inside the referenced account.

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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0, < 5.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.72.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_automation_account.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_account) | resource |
| [azurerm_automation_certificate.certificates](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_certificate) | resource |
| [azurerm_automation_connection_service_principal.service_principal_connections](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_connection_service_principal) | resource |
| [azurerm_automation_connection_type.connection_types](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_connection_type) | resource |
| [azurerm_automation_job_schedule.job_schedules](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_job_schedule) | resource |
| [azurerm_automation_module.modules](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_module) | resource |
| [azurerm_automation_powershell72_module.modules](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_powershell72_module) | resource |
| [azurerm_automation_runbook.index_optimize](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_runbook) | resource |
| [azurerm_automation_runbook.runbooks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_runbook) | resource |
| [azurerm_automation_runbook.webhook](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_runbook) | resource |
| [azurerm_automation_schedule.schedules](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_schedule) | resource |
| [azurerm_automation_webhook.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/automation_webhook) | resource |
| [azurerm_automation_account.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/automation_account) | data source |
| [local_file.index_optimize](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.teams-webhook](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_automation_modules"></a> [automation\_modules](#input\_automation\_modules) | A map of PowerShell 5.1 (Windows PowerShell) modules to install in the automation account. Use var.powershell72\_modules for PS7.x runbooks. | `map(string)` | `{}` | no |
| <a name="input_certificates"></a> [certificates](#input\_certificates) | A map of certificates to create in the automation account. | <pre>map(object({<br/>    base64      = string<br/>    description = optional(string, "")<br/>    exportable  = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_connection_types"></a> [connection\_types](#input\_connection\_types) | A map of connection types to create in the automation account. | `map(map(string))` | `{}` | no |
| <a name="input_create_automation_account"></a> [create\_automation\_account](#input\_create\_automation\_account) | Whether to create a new automation account. If false, an existing account is referenced via existing\_automation\_account\_name and existing\_automation\_account\_resource\_group\_name. | `bool` | `true` | no |
| <a name="input_enable_index_optimize"></a> [enable\_index\_optimize](#input\_enable\_index\_optimize) | If true, create a built-in IndexOptimize runbook (Ola Hallengren) using the bundled script. Auth uses the Automation Account's managed identity. | `bool` | `false` | no |
| <a name="input_existing_automation_account_name"></a> [existing\_automation\_account\_name](#input\_existing\_automation\_account\_name) | The name of an existing automation account to use when create\_automation\_account is false. | `string` | `""` | no |
| <a name="input_existing_automation_account_resource_group_name"></a> [existing\_automation\_account\_resource\_group\_name](#input\_existing\_automation\_account\_resource\_group\_name) | The resource group name of an existing automation account to use when create\_automation\_account is false. | `string` | `""` | no |
| <a name="input_index_optimize_log_progress"></a> [index\_optimize\_log\_progress](#input\_index\_optimize\_log\_progress) | Enable progress logging on the built-in IndexOptimize runbook. Defaults to false. | `bool` | `false` | no |
| <a name="input_index_optimize_log_verbose"></a> [index\_optimize\_log\_verbose](#input\_index\_optimize\_log\_verbose) | Enable verbose logging on the built-in IndexOptimize runbook. Defaults to false to keep job stream volume manageable. | `bool` | `false` | no |
| <a name="input_index_optimize_targets"></a> [index\_optimize\_targets](#input\_index\_optimize\_targets) | Per-target IndexOptimize configuration. Map key becomes the schedule/job suffix (indexoptimize-<key>). | <pre>map(object({<br/>    sql_server                            = string<br/>    database                              = string<br/>    week_days                             = list(string)<br/>    start_time                            = string<br/>    timezone                              = optional(string, "America/New_York")<br/>    description                           = optional(string, "")<br/>    fragmentation_level_1                 = optional(number, 5)<br/>    fragmentation_level_2                 = optional(number, 30)<br/>    fragmentation_low                     = optional(string, null)<br/>    fragmentation_medium                  = optional(string, "INDEX_REBUILD_ONLINE")<br/>    fragmentation_high                    = optional(string, "INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE")<br/>    sort_in_tempdb                        = optional(string, null)<br/>    max_dop                               = optional(number, null)<br/>    fill_factor                           = optional(number, null)<br/>    update_statistics                     = optional(string, "ALL")<br/>    only_modified_statistics              = optional(string, "Y")<br/>    time_limit_minutes                    = optional(number, null)<br/>    wait_at_low_priority_max_duration     = optional(number, 10)<br/>    wait_at_low_priority_abort_after_wait = optional(string, "SELF")<br/>    lock_timeout                          = optional(number, 600)<br/>    lock_message_severity                 = optional(number, 10)<br/>    log_to_table                          = optional(string, "N")<br/>    execute_as_user                       = optional(string, null)<br/>  }))</pre> | `{}` | no |
| <a name="input_job_schedules"></a> [job\_schedules](#input\_job\_schedules) | A map of job schedules to create in the automation account. Merged with job\_schedules derived from var.index\_optimize\_targets when var.enable\_index\_optimize is true. | <pre>map(object({<br/>    runbook_name  = string<br/>    schedule_name = string<br/>    parameters    = optional(map(string), null)<br/>  }))</pre> | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | The location where the automation account should be created. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name of the automation account. | `string` | n/a | yes |
| <a name="input_powershell72_modules"></a> [powershell72\_modules](#input\_powershell72\_modules) | A map of PowerShell 7.x modules to install in the automation account, keyed by module name with the package URI as the value. Required for any PowerShell72 runbook that imports a module. | `map(string)` | `{}` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether public network access is enabled for the Automation Account. Defaults to false for security. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group in which to create the automation account. | `string` | n/a | yes |
| <a name="input_runbooks"></a> [runbooks](#input\_runbooks) | A map of runbooks to create in the automation account. | <pre>map(object({<br/>    runbook_type = string<br/>    description  = optional(string, "")<br/>    content_path = optional(string, "")<br/>    content      = optional(string, "")<br/>    log_verbose  = optional(bool, false)<br/>    log_progress = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_schedules"></a> [schedules](#input\_schedules) | A map of schedules to create in the automation account. Merged with schedules derived from var.index\_optimize\_targets when var.enable\_index\_optimize is true. | <pre>map(object({<br/>    frequency   = string<br/>    timezone    = string<br/>    week_days   = optional(list(string), null)<br/>    month_days  = optional(list(number), null)<br/>    start_time  = optional(string, null)<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |
| <a name="input_service_principal_connections"></a> [service\_principal\_connections](#input\_service\_principal\_connections) | A map of service principal connections to create in the automation account. | <pre>map(object({<br/>    application_id         = string<br/>    certificate_thumbprint = string<br/>    subscription_id        = string<br/>    tenant_id              = string<br/>    description            = optional(string, "")<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resource. | `map(string)` | `{}` | no |
| <a name="input_teams_webhook_expiry"></a> [teams\_webhook\_expiry](#input\_teams\_webhook\_expiry) | Expiry timestamp (RFC3339) for the Teams webhook resource. Plan to rotate or extend by 2030-Q3. | `string` | `"2030-12-31T00:00:00Z"` | no |
| <a name="input_teams_webhook_url"></a> [teams\_webhook\_url](#input\_teams\_webhook\_url) | The URL of the Teams webhook to send notifications to. Treated as a secret - bearer credential. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_certificates"></a> [certificates](#output\_certificates) | Certificates - {id, name} per key. |
| <a name="output_id"></a> [id](#output\_id) | The ID of the Automation Account. |
| <a name="output_identity"></a> [identity](#output\_identity) | The identity of the Automation Account. |
| <a name="output_index_optimize_runbook_name"></a> [index\_optimize\_runbook\_name](#output\_index\_optimize\_runbook\_name) | The name of the built-in IndexOptimize runbook (null if not enabled). |
| <a name="output_job_schedules"></a> [job\_schedules](#output\_job\_schedules) | Job schedules - {id} per key. Job schedules don't have a 'name', they have a job\_schedule\_id (the resource id). |
| <a name="output_name"></a> [name](#output\_name) | The name of the Automation Account. |
| <a name="output_runbooks"></a> [runbooks](#output\_runbooks) | Runbooks - {id, name} per key. |
| <a name="output_schedules"></a> [schedules](#output\_schedules) | Schedules (caller-supplied + index\_optimize-derived) - {id, name} per key. |
| <a name="output_service_principal_connections"></a> [service\_principal\_connections](#output\_service\_principal\_connections) | Service principal connections - {id, name, application\_id} per key. |
| <a name="output_teams_webhook_uri"></a> [teams\_webhook\_uri](#output\_teams\_webhook\_uri) | The URI of the Teams webhook, if created. Bearer credential - sensitive. |
<!-- END_TF_DOCS -->

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

7. **Webhook URLs in state.** `teams_webhook_url` is marked `sensitive` so it
   does not appear in plan output, but Terraform state files are not encrypted
   by default. Store state in a secure backend (e.g., Azure Storage with
   encryption, Terraform Cloud) and restrict access.

8. **Public network access is disabled by default.** New Automation Accounts
   are created with `public_network_access_enabled = false`. Enable only if
   your runbooks need to reach public endpoints and you are not using
   private endpoints.

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
