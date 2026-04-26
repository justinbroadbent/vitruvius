output "tags" {
  value       = local.tags
  description = "Map of tag key to value. Pass directly to Azure resources' `tags` argument. Required tags are always present; optional tags are present only when supplied."
}

output "required_tags" {
  value       = local.required_tags
  description = "Subset of the tag map containing only the five required tags from ADR 0010."
}

output "vocabularies" {
  value       = local.vocabularies
  description = "Allowed values for each vocabulary-controlled tag. Single source of truth for downstream consumers and Backstage form rendering."
}

output "initiative_id" {
  value       = local.deploy_policy ? azurerm_management_group_policy_set_definition.this[0].id : null
  description = "Resource ID of the tag-taxonomy initiative. Null when policy is not deployed (policy_management_group_id was not supplied)."
}

output "policy_definition_ids" {
  value       = { for k, def in azurerm_policy_definition.this : k => def.id }
  description = "Map of policy key to definition ID. Empty when policy is not deployed."
}

output "assignment_id" {
  value       = local.deploy_policy ? azurerm_management_group_policy_assignment.this[0].id : null
  description = "Resource ID of the initiative assignment. Null when policy is not deployed."
}
