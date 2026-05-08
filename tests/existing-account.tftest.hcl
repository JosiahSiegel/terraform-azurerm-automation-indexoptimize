# =============================================================================
# terraform test — create_automation_account = false code path
# =============================================================================
# Uses mock_provider so no Azure credentials are required. This exercises the
# data-source path (data.azurerm_automation_account.existing) and ensures the
# module can plan when referencing an existing Automation Account.
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_automation_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing/providers/Microsoft.Automation/automationAccounts/existing-auto-account"
    }
  }
}

run "plan_with_existing_account" {
  command = plan

  variables {
    name                = "existing-auto-account"
    location            = "eastus"
    resource_group_name = "rg-test"

    create_automation_account                       = false
    existing_automation_account_name                = "existing-auto-account"
    existing_automation_account_resource_group_name = "rg-existing"

    enable_index_optimize = true

    index_optimize_targets = {
      "proddb-weekly" = {
        sql_server = "prodserver.database.windows.net"
        database   = "ProdDatabase"
        week_days  = ["Sunday"]
        start_time = "2026-06-07T02:00:00-04:00"
      }
    }

    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = data.azurerm_automation_account.existing[0].name == "existing-auto-account"
    error_message = "Existing automation account data source name did not match."
  }
}
