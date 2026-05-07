output "id" {
  description = "The ID of the Automation Account."
  value       = azurerm_automation_account.default.id
}

output "name" {
  description = "The name of the Automation Account."
  value       = azurerm_automation_account.default.name
}

output "identity" {
  description = "The identity of the Automation Account."
  value       = azurerm_automation_account.default.identity
}

# Narrow projection: expose only id, name, application_id. Marked sensitive
# because a service principal application_id paired with a thumbprint can be
# used to identify a privileged automation principal.
output "service_principal_connections" {
  description = "Service principal connections - {id, name, application_id} per key."
  value = {
    for k, v in azurerm_automation_connection_service_principal.service_principal_connections : k => {
      id             = v.id
      name           = v.name
      application_id = v.application_id
    }
  }
  sensitive = true
}

output "runbooks" {
  description = "Runbooks - {id, name} per key."
  value = {
    for k, v in azurerm_automation_runbook.runbooks : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "schedules" {
  description = "Schedules (caller-supplied + index_optimize-derived) - {id, name} per key."
  value = {
    for k, v in azurerm_automation_schedule.schedules : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "job_schedules" {
  description = "Job schedules - {id} per key. Job schedules don't have a 'name', they have a job_schedule_id (the resource id)."
  value = {
    for k, v in azurerm_automation_job_schedule.job_schedules : k => {
      id = v.id
    }
  }
}

output "certificates" {
  description = "Certificates - {id, name} per key."
  value = {
    for k, v in azurerm_automation_certificate.certificates : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "teams_webhook_uri" {
  description = "The URI of the Teams webhook, if created. Bearer credential - sensitive."
  value       = length(azurerm_automation_webhook.default) > 0 ? azurerm_automation_webhook.default["default"].uri : null
  sensitive   = true
}

# Reference for callers needing the IndexOptimize runbook name in
# job_schedules.runbook_name. Returns null when the feature is disabled.
output "index_optimize_runbook_name" {
  description = "The name of the built-in IndexOptimize runbook (null if not enabled)."
  value       = length(azurerm_automation_runbook.index_optimize) > 0 ? azurerm_automation_runbook.index_optimize["default"].name : null
}
