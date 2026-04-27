output "covered_resource_types" {
  value       = local.covered_resource_types
  description = "Sorted list of Azure resource types covered by the initiative. Useful for documentation, dashboards, and verifying coverage drift in PR review."
}

output "initiative_id" {
  value       = local.deploy_policy ? azurerm_management_group_policy_set_definition.this[0].id : null
  description = "Resource ID of the substrate diagnostic-settings initiative. Null when policy is not deployed."
}

output "policy_definition_ids" {
  value       = { for k, def in azurerm_policy_definition.this : k => def.id }
  description = "Map of policy key to definition ID. Empty when policy is not deployed."
}

output "assignment_id" {
  value       = local.deploy_assignment ? azurerm_management_group_policy_assignment.this[0].id : null
  description = "Resource ID of the initiative assignment. Null when policy_assignment_scope was not supplied."
}
