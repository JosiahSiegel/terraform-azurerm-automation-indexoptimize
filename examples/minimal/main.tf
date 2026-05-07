# =============================================================================
# Minimal example: one Automation Account, one target database, weekly
# IndexOptimize on Saturdays at 03:00 ET.
#
# After apply, run on the target database (as the Entra admin):
#
#     CREATE USER [example-indexopt-auto] FROM EXTERNAL PROVIDER;
#     ALTER ROLE db_owner ADD MEMBER [example-indexopt-auto];
#
# Then trigger the runbook from the portal with parameters:
#     sqlserver = "myserver.database.windows.net"
#     database  = "MyDatabase"
# to validate the install/run/cleanup flow before the schedule fires.
# =============================================================================

resource "azurerm_resource_group" "example" {
  name     = "rg-indexopt-example"
  location = "eastus"
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
    Example   = "minimal"
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
