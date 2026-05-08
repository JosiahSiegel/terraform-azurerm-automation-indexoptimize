# =============================================================================
# terraform test — minimal example scenario
# =============================================================================
# Replicates the variable surface of examples/minimal using mock_provider.
# Exercises the create_automation_account = true path with a single
# IndexOptimize target.
# =============================================================================

mock_provider "azurerm" {}

run "plan_minimal_scenario" {
  command = plan

  variables {
    name                = "example-indexopt-auto"
    location            = "eastus"
    resource_group_name = "rg-indexopt-example"

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
      Example   = "minimal"
      ManagedBy = "Terraform"
    }
  }

  assert {
    condition     = azurerm_automation_account.default[0].name == "example-indexopt-auto"
    error_message = "Automation account name did not match minimal example scenario."
  }

  assert {
    condition     = azurerm_automation_runbook.index_optimize["default"].name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in minimal example scenario."
  }
}
