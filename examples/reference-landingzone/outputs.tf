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

output "hub_virtual_network_id" {
  value       = module.hub.virtual_network_id
  description = "The hub VNet — the surface spoke roots peer to (ADR 0018 §6)."
}

output "private_dns_zone_ids" {
  value       = module.hub.private_dns_zone_ids
  description = "The hub's centralized private DNS zones — workload roots wire these into their private_endpoints inputs."
}

output "ampls_id" {
  value       = module.hub.ampls_id
  description = "The AMPLS the substrate's resources are scoped into."
}

output "policy_baseline_initiative_id" {
  value       = module.policy_baseline.initiative_id
  description = "The estate policy-baseline initiative, created and assigned at the platform management group (ADR 0025 §1)."
}
