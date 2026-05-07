# =============================================================================
# Automation Account - failed-job alerting
# =============================================================================
# Wraps an action group + a scheduled query rule v2 that fires when an
# Automation runbook job fails or surfaces an error stream.
#
# Greenfield-LAW workaround
# -----------------------------------------------------------------------------
# AutomationJobStreams and AutomationJobLogs are NOT pre-registered in the
# workspace by the diagnostic-setting attach alone. The first row of telemetry
# from a runbook execution materializes the table schema; until then those
# tables don't exist and Azure rejects the alert at create time with:
#
#   "Operator source expression should be table or column.
#    A semantic error occurred." (SEM0104)
#
# `union isfuzzy=true` tolerates *missing* tables for the union itself, but
# if EVERY arm is missing, the union has no schema to bind
# `summarize ... by RunbookName, signal` against and the whole query fails
# semantic validation. The provider's `skip_query_validation` flag does NOT
# bypass this - the Azure API ignores it (terraform-provider-azurerm#28293,
# MS Q&A #2224561).
#
# Fix: anchor the union with a `datatable` stub that publishes the exact
# schema (_ResourceId, StreamType, ResultType, RunbookName, signal) the
# downstream pipeline needs. The stub has zero rows so it never produces
# false positives. Once a runbook actually runs and materializes
# AutomationJobStreams / AutomationJobLogs, the fuzzy arms light up and the
# alert begins firing on real failures.
#
# _ResourceId is lowercased by LAW ingestion - the template lowercases the
# automation_account_name input to match.
# =============================================================================

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.email_receivers
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email_address
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  name                = var.alert_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  description             = var.description
  display_name            = var.display_name
  severity                = var.severity
  enabled                 = true
  auto_mitigation_enabled = true
  evaluation_frequency    = var.evaluation_frequency
  window_duration         = var.window_duration

  scopes = [var.law_id]

  criteria {
    query = templatefile("${path.module}/templates/automation_failures.kql.tftpl", {
      automation_account_name_lower = lower(var.automation_account_name)
    })
    operator                = "GreaterThanOrEqual"
    threshold               = 1
    time_aggregation_method = "Count"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }
}
