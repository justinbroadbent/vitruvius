output "workload_identity_client_id" {
  value       = module.web_api.workload_identity_client_id
  description = "Annotate the Kubernetes ServiceAccount with this (azure.workload.identity/client-id)."
}

output "key_vault_uri" {
  value       = module.web_api.key_vault_uri
  description = "The vault the application reads secrets from — reachable only via the private endpoint."
}

output "resource_group_name" {
  value       = azurerm_resource_group.workload.name
  description = "The workload's resource group, named by the platform convention."
}
