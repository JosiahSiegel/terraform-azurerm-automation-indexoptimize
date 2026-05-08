# =============================================================================
# terraform test — minimal example plan validation
# =============================================================================
# Uses mock_provider so no Azure credentials are required. This exercises the
# plan graph for the minimal example (create_automation_account = true,
# one IndexOptimize target).
# =============================================================================

mock_provider "azurerm" {}

run "plan_minimal_example" {
  command = plan

  assert {
    condition     = module.indexoptimize.name == "example-indexopt-auto"
    error_message = "Automation account name from minimal example did not match."
  }

  assert {
    condition     = module.indexoptimize.index_optimize_runbook_name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in minimal example."
  }
}
