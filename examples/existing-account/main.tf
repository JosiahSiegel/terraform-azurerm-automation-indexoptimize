# =============================================================================
# Existing Automation Account example
#
# This example exercises create_automation_account = false. It references an
# existing Automation Account via data source and deploys the IndexOptimize
# runbook, schedules, and modules into it.
#
# In a real deployment the resource group and automation account would already
# exist; here we create them so the example is self-contained for actual apply
# testing. For plan-only CI testing, the module path (create_automation_account
# = false) is validated via tests/existing-account.tftest.hcl using mock_provider.
# =============================================================================

resource "azurerm_resource_group" "example" {
  name     = "rg-indexopt-existing-example"
  location = "eastus"
}

resource "azurerm_automation_account" "example" {
  name                = "example-indexopt-existing"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Example   = "existing-account"
    ManagedBy = "Terraform"
  }
}

module "indexoptimize" {
  source = "../.."

  create_automation_account                       = false
  existing_automation_account_name                = azurerm_automation_account.example.name
  existing_automation_account_resource_group_name = azurerm_resource_group.example.name

  name                = azurerm_automation_account.example.name
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
    Example   = "existing-account"
    ManagedBy = "Terraform"
  }
}

output "automation_account_name" {
  value       = module.indexoptimize.name
  description = "Name of the existing Automation Account used by the module."
}

output "index_optimize_runbook_name" {
  value       = module.indexoptimize.index_optimize_runbook_name
  description = "Runbook name in the Automation Account."
}
