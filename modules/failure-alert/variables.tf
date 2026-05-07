variable "automation_account_name" {
  description = "Name of the Automation Account whose runbook job failures this alert covers. The KQL query lowercases this value to match LAW's _ResourceId field."
  type        = string
}

variable "law_id" {
  description = "Resource ID of the Log Analytics Workspace the scheduled query runs against."
  type        = string
}

variable "action_group_name" {
  description = "Name of the Azure Monitor action group."
  type        = string
}

variable "action_group_short_name" {
  description = "Short name for the action group (max 12 chars). Appears in SMS/email subjects."
  type        = string

  validation {
    condition     = length(var.action_group_short_name) > 0 && length(var.action_group_short_name) <= 12
    error_message = "action_group_short_name must be between 1 and 12 characters."
  }
}

variable "alert_name" {
  description = "Name of the scheduled query alert resource."
  type        = string
}

variable "email_receivers" {
  description = "List of email receivers to wire to the action group."
  type = list(object({
    name          = string
    email_address = string
  }))

  validation {
    condition     = length(var.email_receivers) > 0
    error_message = "At least one email_receiver must be supplied."
  }
}

variable "location" {
  description = "Azure region for the alert resource."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group hosting the action group + alert resources."
  type        = string
}

variable "tags" {
  description = "Tags to apply to the alert resources."
  type        = map(string)
  default     = {}
}

variable "display_name" {
  description = "Display name shown in the Azure portal alert list."
  type        = string
}

variable "description" {
  description = "Long-form description of the alert."
  type        = string
}

variable "severity" {
  description = "Alert severity (0-4). Default 2."
  type        = number
  default     = 2

  validation {
    condition     = var.severity >= 0 && var.severity <= 4
    error_message = "severity must be 0, 1, 2, 3, or 4."
  }
}

variable "evaluation_frequency" {
  description = "How often the scheduled query runs (ISO8601 duration). Default PT15M."
  type        = string
  default     = "PT15M"
}

variable "window_duration" {
  description = "Time window the query covers (ISO8601 duration). Default PT30M."
  type        = string
  default     = "PT30M"
}
