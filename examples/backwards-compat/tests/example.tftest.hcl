# =============================================================================
# terraform test — backwards-compat example plan validation
# =============================================================================
# Uses mock_provider so no Azure credentials are required. This exercises the
# original variable surface (no existing-account support) to ensure consumers
# who upgrade the module without changing their code encounter no plan errors.
# =============================================================================

mock_provider "azurerm" {}

run "plan_backwards_compat_example" {
  command = plan

  assert {
    condition     = module.indexoptimize.name == "example-indexopt-backcompat"
    error_message = "Automation account name from backwards-compat example did not match."
  }

  assert {
    condition     = module.indexoptimize.index_optimize_runbook_name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created in backwards-compat example."
  }
}
