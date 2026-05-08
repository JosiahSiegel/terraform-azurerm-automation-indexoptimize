# =============================================================================
# terraform test — failure-alert example scenario
# =============================================================================
# Replicates the module variable surface of examples/failure-alert using
# mock_provider. The example also creates a Log Analytics workspace, diagnostic
# setting, and scheduled query alert via a submodule — those are validated by
# terraform validate in the example directory.
# =============================================================================

mock_provider "azurerm" {}

run "plan_failure_alert_scenario" {
  command = plan

  variables {
    name                = "example-indexopt-auto"
    location            = "eastus"
    resource_group_name = "rg-indexopt-alert-example"

    create_automation_account = true

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

  assert {
    condition     = azurerm_automation_account.default[0].name == "example-indexopt-auto"
    error_message = "Automation account name did not match failure-alert example scenario."
  }

  assert {
    condition     = azurerm_automation_runbook.index_optimize["default"].name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in failure-alert example scenario."
  }
}
