# =============================================================================
# Backwards-compatibility example
#
# This example exercises ONLY the original variable surface (pre-existing
# Automation Account support). It ensures that consumers who upgrade the module
# without changing their code do not encounter breaking changes.
# =============================================================================

resource "azurerm_resource_group" "example" {
  name     = "rg-indexopt-backcompat"
  location = "eastus"
}

module "indexoptimize" {
  source = "../.."

  name                = "example-indexopt-backcompat"
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
    Example   = "backwards-compat"
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
