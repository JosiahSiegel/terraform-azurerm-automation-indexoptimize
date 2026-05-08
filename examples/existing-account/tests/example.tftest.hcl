# =============================================================================
# terraform test — existing-account example plan validation
# =============================================================================
# Uses mock_provider so no Azure credentials are required. This exercises the
# data-source path (data.azurerm_automation_account.existing) through the
# example module call with create_automation_account = false.
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_automation_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-indexopt-existing-example/providers/Microsoft.Automation/automationAccounts/example-indexopt-existing"
    }
  }
}

run "plan_existing_account_example" {
  command = plan

  assert {
    condition     = module.indexoptimize.name == "example-indexopt-existing"
    error_message = "Automation account name from existing-account example did not match."
  }

  assert {
    condition     = module.indexoptimize.index_optimize_runbook_name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in existing-account example."
  }
}
