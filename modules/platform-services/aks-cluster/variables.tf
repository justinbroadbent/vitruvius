# --- Placement (consumer supplies pre-computed names per ADR 0004) ---

variable "name" {
  type        = string
  description = "AKS cluster name. Compute via foundation/naming and pass in."

  validation {
    # Azure AKS name: 1-63 chars, alphanumeric + hyphens, start/end alphanumeric.
    condition     = can(regex("^aks-[a-z0-9]([a-z0-9-]{0,57}[a-z0-9])?$", var.name))
    error_message = "name must start with 'aks-' (foundation/naming convention), be at most 63 chars, and end alphanumeric."
  }
}

variable "resource_group_id" {
  type        = string
  description = "Resource ID of the resource group where the cluster is created. The AVM managed-cluster module is azapi-based and takes the parent resource ID, not the group name."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "resource_group_id must be a resource group resource ID (/subscriptions/<sub>/resourceGroups/<name>)."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the cluster."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a lowercase Azure region name (e.g., 'eastus')."
  }
}

variable "node_subnet_id" {
  type        = string
  description = "Resource ID of the subnet the system node pool joins. The cluster is private and uses Azure CNI, so the nodes live in the platform's spoke/hub network (ADR 0018)."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.node_subnet_id))
    error_message = "node_subnet_id must be a subnet resource ID (.../virtualNetworks/<vnet>/subnets/<subnet>)."
  }
}

# --- Observability (consumer supplies the platform LAW) ---

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace receiving the cluster's diagnostic logs. Per ADR 0005 all platform observability flows through the substrate."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a Log Analytics workspace resource ID."
  }
}

# --- Access (local accounts are disabled, so an Entra admin path is required) ---

variable "admin_group_object_ids" {
  type        = list(string)
  description = "Entra ID group object IDs granted cluster-admin through Azure RBAC. Required: the cluster disables local accounts (ADR 0009), so without at least one admin group there is no way in."

  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "admin_group_object_ids must contain at least one Entra group — local accounts are disabled, so an Entra admin path is mandatory."
  }

  validation {
    condition     = alltrue([for g in var.admin_group_object_ids : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", g))])
    error_message = "each admin_group_object_ids entry must be a GUID."
  }
}

# --- Tagging (consumer supplies via foundation/tags per ADR 0010) ---

variable "tags" {
  type        = map(string)
  description = "Tag map produced by the foundation/tags module. Required tags are validated by Azure Policy at the assignment scope, not by this module."

  validation {
    condition = (
      contains(keys(var.tags), "owner") &&
      contains(keys(var.tags), "env") &&
      contains(keys(var.tags), "cost-center") &&
      contains(keys(var.tags), "data-classification") &&
      contains(keys(var.tags), "business-criticality")
    )
    error_message = "tags must include the five required keys from ADR 0010: owner, env, cost-center, data-classification, business-criticality. Use the foundation/tags module to produce this map."
  }
}

# --- Tunables (hardened defaults; the security posture below is NOT tunable) ---

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Kubernetes minor version (e.g., '1.30'). Null lets AKS pick the default for the region. Patch is governed by upgrade_channel, not pinned here."

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must look like '1.30' or '1.30.4' when set."
  }
}

variable "system_node_pool" {
  type = object({
    vm_size            = optional(string, "Standard_D4s_v5")
    node_count         = optional(number, 3)
    min_count          = optional(number)
    max_count          = optional(number)
    availability_zones = optional(list(string), ["1", "2", "3"])
    max_pods           = optional(number, 110)
    os_disk_size_gb    = optional(number, 128)
    os_disk_type       = optional(string, "Managed")
  })
  default     = {}
  description = "System node pool shape. Defaults are a zone-redundant 3-node Standard_D4s_v5 pool. Set min_count/max_count to enable the cluster autoscaler."

  validation {
    condition     = var.system_node_pool.node_count >= 1
    error_message = "system_node_pool.node_count must be at least 1."
  }

  validation {
    condition     = contains(["Managed", "Ephemeral"], var.system_node_pool.os_disk_type)
    error_message = "system_node_pool.os_disk_type must be one of: Managed, Ephemeral."
  }
}

variable "network" {
  type = object({
    network_policy = optional(string, "cilium")
    service_cidr   = optional(string, "172.16.0.0/16")
    dns_service_ip = optional(string, "172.16.0.10")
    pod_cidr       = optional(string, "10.244.0.0/16")
  })
  default     = {}
  description = "Cluster networking. Fixed to Azure CNI overlay; only the policy engine and CIDRs are tunable. Defaults are non-overlapping RFC1918 ranges for an overlay cluster."

  validation {
    condition     = contains(["cilium", "azure", "calico"], var.network.network_policy)
    error_message = "network.network_policy must be one of: cilium, azure, calico."
  }
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = "Resource ID of a private DNS zone (privatelink.<region>.azmk8s.io) for the private API server, typically the hub's centralized zone (ADR 0018). Null lets AKS manage the zone ('System')."
}

variable "authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the API server. The cluster is private; this further restricts the (private) endpoint and any public FQDN. Empty means no extra IP allow-list."
}

variable "user_assigned_identity_id" {
  type        = string
  default     = null
  description = "Resource ID of a user-assigned managed identity for the control plane (e.g., foundation/identity's deploy UAI). Null uses a system-assigned identity created with the cluster."
}

variable "upgrade_channel" {
  type        = string
  default     = "stable"
  description = "AKS automatic upgrade channel for the Kubernetes version. Node-image upgrades are always on ('NodeImage')."

  validation {
    condition     = contains(["none", "patch", "stable", "rapid", "node-image"], var.upgrade_channel)
    error_message = "upgrade_channel must be one of: none, patch, stable, rapid, node-image."
  }
}
