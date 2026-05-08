# =============================================================================
# terraform test — failure-alert example plan validation
# =============================================================================
# Uses mock_provider so no Azure credentials are required. This exercises the
# plan graph for the failure-alert example (Automation Account + Log Analytics
# diagnostic setting + scheduled query alert via submodule).
# =============================================================================

mock_provider "azurerm" {}

run "plan_failure_alert_example" {
  command = plan

  assert {
    condition     = module.indexoptimize.name == "example-indexopt-auto"
    error_message = "Automation account name from failure-alert example did not match."
  }

  assert {
    condition     = module.indexoptimize.index_optimize_runbook_name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in failure-alert example."
  }
}
