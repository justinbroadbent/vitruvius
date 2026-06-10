# The ADR 0018 §6 output contract, minus the firewall surface (firewall
# private IP, route-table IDs) which ships with the deferred v0.2 egress
# work — see the README.

output "virtual_network_id" {
  value       = module.virtual_network.resource_id
  description = "Hub VNet resource ID. Spoke roots peer to this at the consumer boundary (ADR 0004)."
}

output "virtual_network_name" {
  value       = module.virtual_network.name
  description = "Hub VNet name."
}

output "address_space" {
  value       = var.address_space
  description = "The hub's address space, echoed for the consumer's addressing records (ADR 0018 discipline)."
}

output "subnet_ids" {
  value       = { for k, s in module.virtual_network.subnets : k => s.resource_id }
  description = "Map of subnet key to subnet resource ID."
}

output "private_dns_zone_ids" {
  value       = { for z, m in module.private_dns_zones : z => m.resource_id }
  description = "Map of private DNS zone name to zone resource ID. Workload patterns take these as inputs (e.g. web-api-aks private_endpoints)."
}

output "ampls_id" {
  value       = var.create_ampls ? azurerm_monitor_private_link_scope.this[0].id : null
  description = "Azure Monitor Private Link Scope resource ID. Null when create_ampls = false."
}

output "ampls_private_endpoint_id" {
  value       = local.create_ampls_endpoint ? azurerm_private_endpoint.ampls[0].id : null
  description = "AMPLS private endpoint resource ID. Null when no endpoint subnet was named."
}
