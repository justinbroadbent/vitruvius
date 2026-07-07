# Platform-run AKS cluster (ADR 0026; built on a pinned Azure Verified Module per ADR 0001).
#
# The platform team runs the clusters; workloads federate into them. The security
# posture below is opinionated and NOT tunable through this module's inputs:
#   - private API server (no public control plane),
#   - Entra ID + Azure RBAC for authn/authz, local accounts disabled (ADR 0009),
#   - OIDC issuer + workload identity enabled — this is the seam workloads use:
#     workload-patterns/web-api-aks federates to oidc_issuer_url with no secret,
#   - diagnostics routed to the platform substrate LAW (ADR 0005),
#   - automatic node-image and Kubernetes patching.
# A consumer who needs a different posture forks the module (ADR 0004); they do
# not get there by flipping an input.

module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.6.1"

  # Keeps terraform test hermetic and avoids sending AVM usage telemetry from
  # platform infrastructure. Do not flip it on.
  enable_telemetry = false

  name               = var.name
  parent_id          = var.resource_group_id
  location           = var.location
  kubernetes_version = var.kubernetes_version

  # System node pool: zone-redundant by default, joined to the platform network.
  default_agent_pool = {
    name                = "systempool"
    vm_size             = var.system_node_pool.vm_size
    count_of            = var.system_node_pool.node_count
    min_count           = var.system_node_pool.min_count
    max_count           = var.system_node_pool.max_count
    enable_auto_scaling = var.system_node_pool.min_count != null && var.system_node_pool.max_count != null
    availability_zones  = var.system_node_pool.availability_zones
    max_pods            = var.system_node_pool.max_pods
    os_disk_size_gb     = var.system_node_pool.os_disk_size_gb
    os_disk_type        = var.system_node_pool.os_disk_type
    vnet_subnet_id      = var.node_subnet_id
  }

  # Azure CNI overlay — the only supported dataplane for platform clusters.
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = var.network.network_policy
    service_cidr        = var.network.service_cidr
    dns_service_ip      = var.network.dns_service_ip
    pod_cidr            = var.network.pod_cidr
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # Control-plane identity: a supplied UAI, else system-assigned.
  managed_identities = {
    system_assigned            = var.user_assigned_identity_id == null
    user_assigned_resource_ids = var.user_assigned_identity_id == null ? [] : [var.user_assigned_identity_id]
  }

  # --- The non-tunable hardened posture ---

  # Private API server (ADR 0018: no public control plane).
  api_server_access_profile = {
    enable_private_cluster = true
    private_dns_zone       = var.private_dns_zone_id
    authorized_ip_ranges   = length(var.authorized_ip_ranges) > 0 ? var.authorized_ip_ranges : null
  }

  # Entra ID + Azure RBAC; local accounts off (ADR 0009).
  enable_rbac            = true
  disable_local_accounts = true
  aad_profile = {
    managed                = true
    enable_azure_rbac      = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  # The workload-identity seam: OIDC issuer + workload identity on.
  oidc_issuer_profile = {
    enabled = true
  }
  security_profile = {
    workload_identity = {
      enabled = true
    }
  }

  # Always-on patching; Kubernetes channel is tunable, node image is not.
  auto_upgrade_profile = {
    upgrade_channel         = var.upgrade_channel
    node_os_upgrade_channel = "NodeImage"
  }

  # Diagnostics to the platform substrate LAW (ADR 0005).
  diagnostic_settings = {
    to_substrate_law = {
      name                  = "diag-to-law"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  tags = var.tags
}
