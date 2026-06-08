output "resource_group_name" {
  value       = azurerm_resource_group.platform.name
  description = "The platform resource group, named by foundation/naming."
}

output "tags" {
  value       = module.tags.tags
  description = "The tag map applied to every resource in this root."
}

output "log_analytics_workspace_id" {
  value       = module.observability_substrate.log_analytics_workspace_id
  description = "The substrate workspace ID — consumed by diagnostic-settings here, and the input workload roots wire into."
}

output "application_insights_connection_string" {
  value       = module.observability_substrate.application_insights_connection_string
  description = "The collector's Azure Monitor exporter target."
  sensitive   = true
}

output "deploy_identity_client_id" {
  value       = module.identity.deploy.client_id
  description = "Client ID of the platform deploy UAI."
}

output "substrate_routing_initiative_id" {
  value       = module.diagnostic_settings.initiative_id
  description = "The substrate-routing initiative, created at the platform management group."
}
