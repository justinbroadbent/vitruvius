output "names" {
  value       = local.names
  description = "Map of resource type to canonical Azure resource name. Access by key, e.g., module.naming.names.storage_account."
}

output "region_abbr" {
  value       = local.region_abbr
  description = "Short code for the region used in names (e.g., 'eus' for 'eastus')."
}

output "parts" {
  value = {
    hyphen  = local.parts_hyphen
    compact = local.parts_compact
  }
  description = "Composed name parts available to consumers needing a custom resource type not yet covered by the names map."
}
