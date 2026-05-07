variable "name" {
  description = "The name of the automation account."
  type        = string

  validation {
    # Azure Automation Account naming: must start with letter, end with
    # alphanumeric, and contain only letters, digits, hyphens; 6-50 chars total.
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{4,48}[A-Za-z0-9]$", var.name))
    error_message = "Automation Account name must be 6-50 chars, start with a letter, end with alphanumeric, and contain only letters/digits/hyphens."
  }
}

variable "location" {
  description = "The location where the automation account should be created."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the automation account."
  type        = string
}

variable "tags" {
  description = "A mapping of tags to assign to the resource."
  type        = map(string)
  default     = {}
}

variable "teams_webhook_url" {
  description = "The URL of the Teams webhook to send notifications to. Treated as a secret - bearer credential."
  type        = string
  default     = ""
  sensitive   = true
}

variable "teams_webhook_expiry" {
  description = "Expiry timestamp (RFC3339) for the Teams webhook resource. Plan to rotate or extend by 2030-Q3."
  type        = string
  default     = "2030-12-31T00:00:00Z"
}

variable "automation_modules" {
  description = "A map of PowerShell 5.1 (Windows PowerShell) modules to install in the automation account. Use var.powershell72_modules for PS7.x runbooks."
  type        = map(string)
  default     = {}
}

variable "powershell72_modules" {
  description = "A map of PowerShell 7.x modules to install in the automation account, keyed by module name with the package URI as the value. Required for any PowerShell72 runbook that imports a module."
  type        = map(string)
  default     = {}
}

variable "connection_types" {
  description = "A map of connection types to create in the automation account."
  type        = map(map(string))
  default     = {}
}

variable "service_principal_connections" {
  description = "A map of service principal connections to create in the automation account."
  type = map(object({
    application_id         = string
    certificate_thumbprint = string
    subscription_id        = string
    tenant_id              = string
    description            = optional(string, "")
  }))
  default = {}
}

variable "runbooks" {
  description = "A map of runbooks to create in the automation account."
  type = map(object({
    runbook_type = string
    description  = optional(string, "")
    content_path = optional(string, "")
    content      = optional(string, "")
    log_verbose  = optional(bool, false)
    log_progress = optional(bool, false)
  }))
  default = {}
}

variable "schedules" {
  description = "A map of schedules to create in the automation account. Merged with schedules derived from var.index_optimize_targets when var.enable_index_optimize is true."
  type = map(object({
    frequency   = string
    timezone    = string
    week_days   = optional(list(string), null)
    month_days  = optional(list(number), null)
    start_time  = optional(string, null)
    description = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.schedules : contains(["OneTime", "Hour", "Day", "Week", "Month"], v.frequency)
    ])
    error_message = "Each schedule's frequency must be one of: OneTime, Hour, Day, Week, Month."
  }
}

variable "job_schedules" {
  description = "A map of job schedules to create in the automation account. Merged with job_schedules derived from var.index_optimize_targets when var.enable_index_optimize is true."
  type = map(object({
    runbook_name  = string
    schedule_name = string
    parameters    = optional(map(string), null)
  }))
  default = {}
}

variable "certificates" {
  description = "A map of certificates to create in the automation account."
  type = map(object({
    base64      = string
    description = optional(string, "")
    exportable  = optional(bool, false)
  }))
  default = {}
}

# When true, the module creates a built-in IndexOptimize runbook (Ola
# Hallengren's stored procedure wrapper) using the bundled
# scripts/IndexOptimize.ps1. The runbook authenticates to Azure SQL via the
# Automation Account's SystemAssigned managed identity, so no SQL credential
# is needed. Each target database must have a SQL principal mapped to the MI
# (CREATE USER [<automation-account-name>] FROM EXTERNAL PROVIDER) with
# permissions to execute dbo.IndexOptimize. When enabled, the SqlServer
# PowerShell module is automatically imported into the PS7.x module slot so
# the script can load Microsoft.Data.SqlClient and connect with
# Authentication=Active Directory Managed Identity.
variable "enable_index_optimize" {
  description = "If true, create a built-in IndexOptimize runbook (Ola Hallengren) using the bundled script. Auth uses the Automation Account's managed identity."
  type        = bool
  default     = false
}

variable "index_optimize_log_verbose" {
  description = "Enable verbose logging on the built-in IndexOptimize runbook. Defaults to false to keep job stream volume manageable."
  type        = bool
  default     = false
}

variable "index_optimize_log_progress" {
  description = "Enable progress logging on the built-in IndexOptimize runbook. Defaults to false."
  type        = bool
  default     = false
}

# Per-target IndexOptimize configuration. When var.enable_index_optimize is
# true, each entry produces:
#   - a schedule  : "indexoptimize-<key>" (frequency = Week, timezone +
#                   week_days from the entry; start_time is ignored on drift)
#   - a job link  : "indexoptimize-<key>" bound to the IndexOptimize runbook
#                   with lowercase parameters {sqlserver, database}
# Callers can still inject one-off schedules / job_schedules via var.schedules
# and var.job_schedules - the module merges those with the derived maps.
variable "index_optimize_targets" {
  description = "Per-target IndexOptimize configuration. Map key becomes the schedule/job suffix (indexoptimize-<key>)."
  type = map(object({
    sql_server  = string
    database    = string
    week_days   = list(string)
    start_time  = string
    timezone    = optional(string, "America/New_York")
    description = optional(string, "")
  }))
  default = {}
}
