output "log_analytics_workspace_id" {
  value       = module.log_analytics_workspace.resource_id
  description = "Resource ID of the central Log Analytics workspace. This is the substrate input that foundation/diagnostic-settings and the workload patterns (e.g., web-api-aks) consume as log_analytics_workspace_id."
}

output "application_insights_id" {
  value       = module.application_insights.resource_id
  description = "Resource ID of the workspace-based Application Insights component."
}

output "application_insights_connection_string" {
  value       = module.application_insights.connection_string
  description = "Application Insights connection string — the OTel collector's Azure Monitor exporter target. Prefer this over the instrumentation key."
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  value       = module.application_insights.instrumentation_key
  description = "Application Insights instrumentation key. Legacy; prefer the connection string."
  sensitive   = true
}

output "action_group_id" {
  value       = local.create_action_group ? azurerm_monitor_action_group.platform[0].id : null
  description = "Resource ID of the platform action group. Null when no alert_email_receivers were supplied."
}
