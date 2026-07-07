output "cluster_id" {
  value       = module.aks.resource_id
  description = "Resource ID of the managed cluster."
}

output "cluster_name" {
  value       = module.aks.name
  description = "Name of the managed cluster."
}

output "oidc_issuer_url" {
  value       = module.aks.oidc_issuer_profile_issuer_url
  description = "OIDC issuer URL of the cluster. The seam workloads federate into — pass this to workload-patterns/web-api-aks as aks_oidc_issuer_url."
}

output "node_resource_group_name" {
  value       = module.aks.node_resource_group_name
  description = "Auto-created resource group holding the cluster's node infrastructure (MC_*)."
}

output "kubelet_identity" {
  value       = module.aks.kubelet_identity
  description = "Kubelet identity (clientId/objectId/resourceId) — grant it AcrPull on the platform registry, etc."
}
