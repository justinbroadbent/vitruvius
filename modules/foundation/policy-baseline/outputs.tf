output "guardrail_policies" {
  value       = local.guardrail_policies
  description = "Sorted list of guardrail policy keys bundled in the initiative. Available regardless of deploy mode — useful for documentation and coverage review."
}

output "initiative_id" {
  value       = local.deploy_policy ? azurerm_management_group_policy_set_definition.this[0].id : null
  description = "Resource ID of the estate policy-baseline initiative. Null when policy is not deployed."
}

output "policy_definition_ids" {
  value       = { for k, def in azurerm_policy_definition.this : k => def.id }
  description = "Map of guardrail key to policy definition ID. Empty when policy is not deployed."
}

output "assignment_id" {
  value       = local.deploy_assignment ? azurerm_management_group_policy_assignment.this[0].id : null
  description = "Resource ID of the initiative assignment. Null when policy_assignment_scope was not supplied."
}
