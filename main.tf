resource "azurerm_automation_account" "default" {
  count = var.create_automation_account ? 1 : 0

  name                = var.name
  location            = var.location
  resource_group_name = lower(var.resource_group_name)
  tags                = var.tags

  sku_name = "Basic"

  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }
}

moved {
  from = azurerm_automation_account.default
  to   = azurerm_automation_account.default[0]
}

data "azurerm_automation_account" "existing" {
  count = var.create_automation_account ? 0 : 1

  name                = var.existing_automation_account_name
  resource_group_name = var.existing_automation_account_resource_group_name
}

locals {
  automation_account_id   = var.create_automation_account ? azurerm_automation_account.default[0].id : data.azurerm_automation_account.existing[0].id
  automation_account_name = var.create_automation_account ? azurerm_automation_account.default[0].name : data.azurerm_automation_account.existing[0].name
  automation_account_rg   = var.create_automation_account ? lower(var.resource_group_name) : lower(data.azurerm_automation_account.existing[0].resource_group_name)
}

locals {
  # webhook_enabled is non-sensitive (a bool derived from string equality with
  # a literal). The sensitive teams_webhook_url is consumed only inside the
  # parameters block of azurerm_automation_webhook.default below, where
  # nonsensitive() is NOT applied - the value stays sensitive in state.
  # Splitting presence (used as a for_each key) from value (used as a param)
  # avoids the "for_each derived from sensitive value" error while keeping
  # the URL itself sensitive end-to-end.
  webhook_enabled = nonsensitive(var.teams_webhook_url != "")
  webhook_keys    = local.webhook_enabled ? { default = "default" } : {}
}

data "local_file" "teams-webhook" {
  filename = "${path.module}/scripts/teams-webhook.ps1"
}

resource "azurerm_automation_runbook" "webhook" {
  for_each                = local.webhook_keys
  name                    = "Notify-Teams"
  location                = var.location
  resource_group_name     = local.automation_account_rg
  automation_account_name = local.automation_account_name
  log_verbose             = true
  log_progress            = true
  description             = "Send a webhook notification to a Microsoft Teams channel."
  runbook_type            = "PowerShell"
  tags                    = var.tags

  content = data.local_file.teams-webhook.content
}

resource "azurerm_automation_webhook" "default" {
  for_each                = local.webhook_keys
  name                    = "Notify-Teams-Webhook"
  resource_group_name     = local.automation_account_rg
  automation_account_name = local.automation_account_name
  expiry_time             = var.teams_webhook_expiry
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.webhook[each.key].name
  parameters = {
    webhookUrl  = var.teams_webhook_url
    webhookData = ""
  }
}

# Add moved blocks to handle state transitions without requiring manual state moves
moved {
  from = azurerm_automation_runbook.webhook
  to   = azurerm_automation_runbook.webhook["default"]
}

moved {
  from = azurerm_automation_webhook.default
  to   = azurerm_automation_webhook.default["default"]
}

locals {
  # When IndexOptimize is enabled, ensure the SqlServer PowerShell module is
  # installed in the PS7.x module slot. The bundled script imports SqlServer
  # to load the Microsoft.Data.SqlClient assembly and connects with
  # Authentication=Active Directory Managed Identity in the connection string,
  # eliminating the prior dependency on Az.Accounts / Get-AzAccessToken.
  #
  # Pinned version: SqlServer 22.3.0. See README.md for the .NET 8 / PS 7.2
  # compatibility analysis behind this pin.
  index_optimize_required_ps72_modules = var.enable_index_optimize ? {
    "SqlServer" = "https://www.powershellgallery.com/api/v2/package/SqlServer/22.3.0"
  } : {}

  effective_ps72_modules = merge(local.index_optimize_required_ps72_modules, var.powershell72_modules)
}

# PowerShell 5.1 / Windows PowerShell module slot. Kept for callers passing
# legacy modules via var.automation_modules. Auto-merge for IndexOptimize no
# longer flows here - it goes to the PS7.x slot below (see B1 fix).
resource "azurerm_automation_module" "modules" {
  for_each                = var.automation_modules
  automation_account_name = local.automation_account_name
  name                    = each.key
  resource_group_name     = local.automation_account_rg

  module_link {
    uri = each.value
  }

  lifecycle {
    ignore_changes = [module_link]
  }
}

# PowerShell 7.x module slot. The IndexOptimize runbook runs under the
# PowerShell72 runtime, which only sees modules installed via this resource.
#
# Intentionally NO `ignore_changes = [module_link]` here. The module_link.uri
# encodes the pinned version (e.g. SqlServer/22.3.0). When that pin changes
# in HCL, apply MUST replace the resource so Azure imports the new bytes.
# An ignore_changes directive would silently mask version bumps and lock the
# Automation Account on whatever version it first imported - exactly the
# failure mode that masked the SqlServer 22.4.5.1 -> 22.3.0 downgrade for
# multiple apply cycles in May 2026 (System.Runtime 8.0.0.0 load failure
# under the PS 7.2 runtime). Microsoft.SQLServerPSModule#111 documents the
# error string.
#
# Use `terraform apply -replace=...` to force re-import on URI change.
resource "azurerm_automation_powershell72_module" "modules" {
  for_each              = local.effective_ps72_modules
  automation_account_id = local.automation_account_id
  name                  = each.key

  module_link {
    uri = each.value
  }
}

resource "azurerm_automation_connection_type" "connection_types" {
  for_each                = var.connection_types
  automation_account_name = local.automation_account_name
  is_global               = true
  name                    = each.key
  resource_group_name     = local.automation_account_rg

  dynamic "field" {
    for_each = each.value
    content {
      name = field.key
      type = field.value
    }
  }

  lifecycle {
    ignore_changes = [field]
  }
}

# Service Principal Connections
resource "azurerm_automation_connection_service_principal" "service_principal_connections" {
  for_each                = var.service_principal_connections
  automation_account_name = local.automation_account_name
  name                    = each.key
  resource_group_name     = local.automation_account_rg
  application_id          = each.value.application_id
  certificate_thumbprint  = each.value.certificate_thumbprint
  subscription_id         = each.value.subscription_id
  tenant_id               = each.value.tenant_id
  description             = each.value.description
}

# Runbooks
resource "azurerm_automation_runbook" "runbooks" {
  for_each                = var.runbooks
  automation_account_name = local.automation_account_name
  name                    = each.key
  location                = var.location
  resource_group_name     = local.automation_account_rg
  runbook_type            = each.value.runbook_type
  description             = each.value.description

  # Determine content with the following precedence:
  #   1. content_path (read file from disk) - most ergonomic for env callers
  #   2. content (inline string)
  #   3. GraphPowerShell skeleton (for graphical runbooks)
  #   4. Placeholder for content managed outside of Terraform
  content = each.value.content_path != "" ? file(each.value.content_path) : (
    each.value.content != "" ? each.value.content : (
      each.value.runbook_type == "GraphPowerShell" ? jsonencode({
        RunbookDefinition = " "
        RunbookType       = "GraphPowerShell"
        SchemaVersion     = "1.7"
      }) : "# Content will be managed outside of Terraform"
    )
  )

  log_verbose  = each.value.log_verbose
  log_progress = each.value.log_progress
  tags         = var.tags

  lifecycle {
    ignore_changes = [content]
  }
}

# -----------------------------------------------------------------------------
# IndexOptimize-derived schedules and job_schedules
# -----------------------------------------------------------------------------
# Project var.index_optimize_targets into the same shape var.schedules and
# var.job_schedules use, then merge so callers can still inject one-off
# schedules. Map keys are "indexoptimize-<target_key>" - identical to the
# pre-refactor env-side projection, preserving resource addresses in state.
locals {
  derived_schedules = {
    for k, t in var.index_optimize_targets : "indexoptimize-${k}" => {
      frequency   = "Week"
      timezone    = t.timezone
      week_days   = t.week_days
      month_days  = null
      start_time  = t.start_time
      description = t.description != "" ? t.description : "Weekly IndexOptimize for ${t.database} on ${t.sql_server}"
    }
  }

  derived_job_schedules = {
    for k, t in var.index_optimize_targets : "indexoptimize-${k}" => {
      runbook_name  = length(azurerm_automation_runbook.index_optimize) > 0 ? azurerm_automation_runbook.index_optimize["default"].name : ""
      schedule_name = "indexoptimize-${k}"
      parameters = {
        sqlserver                       = t.sql_server
        database                        = t.database
        fragmentationlevel1             = tostring(t.fragmentation_level_1)
        fragmentationlevel2             = tostring(t.fragmentation_level_2)
        fragmentationlow                = t.fragmentation_low == null ? "" : t.fragmentation_low
        fragmentationmedium             = t.fragmentation_medium
        fragmentationhigh               = t.fragmentation_high
        sortintempdb                    = t.sort_in_tempdb == null ? "" : t.sort_in_tempdb
        maxdop                          = t.max_dop == null ? "" : tostring(t.max_dop)
        fillfactor                      = t.fill_factor == null ? "" : tostring(t.fill_factor)
        updatestatistics                = t.update_statistics
        onlymodifiedstatistics          = t.only_modified_statistics
        timelimitminutes                = t.time_limit_minutes == null ? "" : tostring(t.time_limit_minutes)
        waitatlowprioritymaxduration    = tostring(t.wait_at_low_priority_max_duration)
        waitatlowpriorityabortafterwait = t.wait_at_low_priority_abort_after_wait
        locktimeout                     = tostring(t.lock_timeout)
        lockmessageseverity             = tostring(t.lock_message_severity)
        logtotable                      = t.log_to_table
        executeasuser                   = t.execute_as_user == null ? "" : t.execute_as_user
      }
    }
  }

  effective_schedules     = merge(local.derived_schedules, var.schedules)
  effective_job_schedules = merge(local.derived_job_schedules, var.job_schedules)
}

# Schedules
resource "azurerm_automation_schedule" "schedules" {
  for_each                = local.effective_schedules
  automation_account_name = local.automation_account_name
  name                    = each.key
  resource_group_name     = local.automation_account_rg
  frequency               = each.value.frequency
  timezone                = each.value.timezone
  description             = each.value.description

  # Optional parameters
  week_days  = each.value.week_days
  month_days = each.value.month_days
  start_time = each.value.start_time

  # C5: start_time only matters for the first occurrence; subsequent fires use
  # frequency + week_days. Ignore drift on start_time to defend against the
  # known azurerm timezone+offset round-trip bug that produces a perpetual diff
  # on weekly schedules. Schedule edits therefore require taint - see README.md.
  lifecycle {
    ignore_changes = [start_time]
  }
}

# Job Schedules
resource "azurerm_automation_job_schedule" "job_schedules" {
  for_each                = local.effective_job_schedules
  automation_account_name = local.automation_account_name
  resource_group_name     = local.automation_account_rg
  runbook_name            = each.value.runbook_name
  schedule_name           = each.value.schedule_name
  parameters              = each.value.parameters
}

# Certificates
resource "azurerm_automation_certificate" "certificates" {
  for_each                = var.certificates
  automation_account_name = local.automation_account_name
  name                    = each.key
  resource_group_name     = local.automation_account_rg
  base64                  = each.value.base64
  description             = each.value.description
  exportable              = each.value.exportable

  lifecycle {
    ignore_changes = [base64]
  }
}

# -----------------------------------------------------------------------------
# Built-in IndexOptimize runbook (Ola Hallengren)
# -----------------------------------------------------------------------------
# Gated by var.enable_index_optimize so the bundled script file is only read
# when the feature is enabled (mirrors the Teams webhook pattern). The script
# authenticates to Azure SQL via the Automation Account's managed identity -
# no SQL credentials, no Key Vault secrets, no password rotation. See README.md
# for the per-DB SQL principal setup and MI-recreate recovery procedure.
locals {
  index_optimize_map = var.enable_index_optimize ? { default = true } : {}
}

data "local_file" "index_optimize" {
  for_each = local.index_optimize_map
  filename = "${path.module}/scripts/IndexOptimize.ps1"
}

resource "azurerm_automation_runbook" "index_optimize" {
  for_each                = local.index_optimize_map
  name                    = "IndexOptimize"
  location                = var.location
  resource_group_name     = local.automation_account_rg
  automation_account_name = local.automation_account_name
  log_verbose             = var.index_optimize_log_verbose
  log_progress            = var.index_optimize_log_progress
  description             = "Ola Hallengren IndexOptimize wrapper. Targets a single SQL database via parameters (SqlServer, Database, SQLCredentialName)."
  runbook_type            = "PowerShell72"
  tags                    = var.tags

  content = data.local_file.index_optimize[each.key].content
}
