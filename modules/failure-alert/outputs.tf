output "action_group_id" {
  description = "Resource ID of the action group."
  value       = azurerm_monitor_action_group.this.id
}

output "alert_id" {
  description = "Resource ID of the scheduled query alert."
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.this.id
}
