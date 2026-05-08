# =============================================================================
# terraform test — create_automation_account = true code path
# =============================================================================
# Uses mock_provider so no Azure credentials are required. This exercises the
# plan graph for the root module when creating a new Automation Account,
# including all derived resources (runbooks, schedules, job_schedules, modules,
# certificates, connections, webhooks).
# =============================================================================

mock_provider "azurerm" {}

run "plan_with_new_account" {
  command = plan

  variables {
    name                = "test-auto-account"
    location            = "eastus"
    resource_group_name = "rg-test"

    create_automation_account = true

    enable_index_optimize = true

    index_optimize_targets = {
      "testdb-weekly" = {
        sql_server = "testserver.database.windows.net"
        database   = "TestDatabase"
        week_days  = ["Saturday"]
        start_time = "2026-06-06T03:00:00-04:00"
      }
    }

    teams_webhook_url = "https://example.webhook.office.com/webhookb2/test"

    automation_modules = {
      "Az.Accounts" = "https://www.powershellgallery.com/api/v2/package/Az.Accounts/3.0.0"
    }

    powershell72_modules = {
      "Az.Resources" = "https://www.powershellgallery.com/api/v2/package/Az.Resources/7.0.0"
    }

    connection_types = {
      "CustomType" = {
        "Field1" = "String"
        "Field2" = "Bool"
      }
    }

    service_principal_connections = {
      "sp-conn" = {
        application_id         = "00000000-0000-0000-0000-000000000001"
        certificate_thumbprint = "AABBCCDDEEFF00112233445566778899AABBCCDD"
        subscription_id        = "00000000-0000-0000-0000-000000000002"
        tenant_id              = "00000000-0000-0000-0000-000000000003"
        description            = "Test SP connection"
      }
    }

    runbooks = {
      "Test-Runbook" = {
        runbook_type = "PowerShell72"
        description  = "A test runbook"
        content      = "Write-Output 'Hello World'"
        log_verbose  = true
        log_progress = true
      }
    }

    schedules = {
      "test-schedule" = {
        frequency   = "Week"
        timezone    = "America/New_York"
        week_days   = ["Sunday"]
        start_time  = "2026-06-07T04:00:00-04:00"
        description = "Test schedule"
      }
    }

    job_schedules = {}

    certificates = {
      "test-cert" = {
        base64      = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM="
        description = "Test certificate"
        exportable  = true
      }
    }

    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = azurerm_automation_account.default[0].name == "test-auto-account"
    error_message = "Automation account name did not match expected value."
  }

  assert {
    condition     = azurerm_automation_runbook.index_optimize["default"].name == "IndexOptimize"
    error_message = "IndexOptimize runbook was not created."
  }
}
