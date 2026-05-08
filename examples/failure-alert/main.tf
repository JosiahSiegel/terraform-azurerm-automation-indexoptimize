# =============================================================================
# Failure-alert example: root module for Automation Account + submodule for
# Log Analytics scheduled query alert on runbook job failures.
#
# This example creates:
#   1. A Resource Group
#   2. A Log Analytics Workspace
#   3. An Automation Account with IndexOptimize (via the root module)
#   4. A diagnostic setting shipping Automation logs to the LAW
#   5. A scheduled query alert + action group (via the failure-alert submodule)
#
# After apply, run on each target database (as the Entra admin):
#
#     CREATE USER [example-indexopt-auto] FROM EXTERNAL PROVIDER;
#     ALTER ROLE db_owner ADD MEMBER [example-indexopt-auto];
# =============================================================================

resource "azurerm_resource_group" "example" {
  name     = "rg-indexopt-alert-example"
  location = "eastus"
}

resource "azurerm_log_analytics_workspace" "example" {
  name                = "law-indexopt-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Example   = "failure-alert"
    ManagedBy = "Terraform"
  }
}

module "indexoptimize" {
  source = "../.."

  name                = "example-indexopt-auto"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

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
    Example   = "failure-alert"
    ManagedBy = "Terraform"
  }
}

# Diagnostic setting: ship Automation logs to the LAW so the alert query has data.
resource "azurerm_monitor_diagnostic_setting" "automation" {
  name                       = "ds-automation-law"
  target_resource_id         = module.indexoptimize.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  enabled_log {
    category = "JobLogs"
  }
  enabled_log {
    category = "JobStreams"
  }
  enabled_log {
    category = "DscNodeStatus"
  }
  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

module "failure_alert" {
  source = "../../modules/failure-alert"

  automation_account_name = module.indexoptimize.name
  law_id                  = azurerm_log_analytics_workspace.example.id
  resource_group_name     = azurerm_resource_group.example.name
  location                = azurerm_resource_group.example.location

  action_group_name       = "ag-indexopt-failures"
  action_group_short_name = "idxoptFail"
  alert_name              = "alert-indexopt-failures"
  display_name            = "IndexOptimize Runbook Failures"
  description             = "Fires when an IndexOptimize runbook job fails or emits an error stream."

  email_receivers = [
    { name = "dba-team", email_address = "dba-oncall@example.com" }
  ]

  tags = {
    Example   = "failure-alert"
    ManagedBy = "Terraform"
  }
}

output "automation_account_name" {
  value       = module.indexoptimize.name
  description = "Use this exact name as the SQL principal in CREATE USER ... FROM EXTERNAL PROVIDER."
}

output "indexoptimize_runbook_name" {
  value       = module.indexoptimize.index_optimize_runbook_name
  description = "Runbook name in the Automation Account."
}

output "alert_id" {
  value       = module.failure_alert.alert_id
  description = "ID of the scheduled query alert."
}

output "action_group_id" {
  value       = module.failure_alert.action_group_id
  description = "ID of the action group."
}
