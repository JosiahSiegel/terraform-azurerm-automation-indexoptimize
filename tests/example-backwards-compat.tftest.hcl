# =============================================================================
# terraform test — backwards-compat example scenario
# =============================================================================
# Replicates the variable surface of examples/backwards-compat using
# mock_provider. Ensures consumers who upgrade without changing their code
# encounter no plan errors.
# =============================================================================

mock_provider "azurerm" {}

run "plan_backwards_compat_scenario" {
  command = plan

  variables {
    name                = "example-indexopt-backcompat"
    location            = "eastus"
    resource_group_name = "rg-indexopt-backcompat"

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
      Example   = "backwards-compat"
      ManagedBy = "Terraform"
    }
  }

  assert {
    condition     = azurerm_automation_account.default[0].name == "example-indexopt-backcompat"
    error_message = "Automation account name did not match backwards-compat example scenario."
  }

  assert {
    condition     = azurerm_automation_runbook.index_optimize["default"].name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in backwards-compat example scenario."
  }
}
