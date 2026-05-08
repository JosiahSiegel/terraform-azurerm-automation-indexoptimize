# =============================================================================
# terraform test — existing-account example scenario
# =============================================================================
# Replicates the variable surface of examples/existing-account using
# mock_provider. Exercises the data-source path for an existing Automation
# Account.
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_automation_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-indexopt-existing-example/providers/Microsoft.Automation/automationAccounts/example-indexopt-existing"
    }
  }
}

run "plan_existing_account_scenario" {
  command = plan

  variables {
    name                = "example-indexopt-existing"
    location            = "eastus"
    resource_group_name = "rg-indexopt-existing-example"

    create_automation_account                       = false
    existing_automation_account_name                = "example-indexopt-existing"
    existing_automation_account_resource_group_name = "rg-indexopt-existing-example"

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
      Example   = "existing-account"
      ManagedBy = "Terraform"
    }
  }

  assert {
    condition     = data.azurerm_automation_account.existing[0].name == "example-indexopt-existing"
    error_message = "Existing automation account data source name did not match."
  }

  assert {
    condition     = azurerm_automation_runbook.index_optimize["default"].name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in existing-account example scenario."
  }
}
