output "workload_identity_client_id" {
  value       = azurerm_user_assigned_identity.workload.client_id
  description = "Client ID of the workload's user-assigned managed identity. Annotate the Kubernetes ServiceAccount with this value to enable workload-identity token exchange: `azure.workload.identity/client-id: <this value>`."
}

output "workload_identity_principal_id" {
  value       = azurerm_user_assigned_identity.workload.principal_id
  description = "Principal (object) ID of the workload's UAI. Use this when granting additional Azure RBAC role assignments outside the module."
}

output "workload_identity_id" {
  value       = azurerm_user_assigned_identity.workload.id
  description = "Resource ID of the UAI."
}

output "key_vault_id" {
  value       = module.key_vault.resource_id
  description = "Resource ID of the workload's Key Vault."
}

output "key_vault_uri" {
  value       = module.key_vault.uri
  description = "Vault URI for the workload's Key Vault. Pass to the application as configuration; the workload identity already has Key Vault Secrets User on it."
}

output "service_account_annotations" {
  value = {
    "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload.client_id
    "azure.workload.identity/tenant-id" = data.azurerm_client_config.current.tenant_id
  }
  description = "Map of annotations the app team must apply to the Kubernetes ServiceAccount named in `aks_service_account_name` for workload-identity federation to function."
}

output "policy_initiative_id" {
  value       = azurerm_policy_set_definition.this.id
  description = "Resource ID of the workload's KV hardening initiative."
}

output "policy_assignment_id" {
  value = (
    local.assign_at_subscription ? azurerm_subscription_policy_assignment.this[0].id :
    local.assign_at_resource_group ? azurerm_resource_group_policy_assignment.this[0].id :
    null
  )
  description = "Resource ID of the policy assignment (subscription- or resource-group-scoped, matching policy_assignment_scope). Null when policy_assignment_scope was not supplied (assignment is then expected to happen at a higher scope)."
}
