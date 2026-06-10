variable "virtual_network_name" {
  type        = string
  description = "Name for the hub virtual network. Compute via foundation/naming and pass in."

  validation {
    condition     = can(regex("^vnet-[a-z0-9-]{2,60}$", var.virtual_network_name))
    error_message = "virtual_network_name must start with 'vnet-' (foundation/naming convention)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the hub network resources are created in. The consumer owns and supplies the RG (ADR 0004 / ADR 0024)."

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the hub resources."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a lowercase Azure region name (e.g., 'eastus')."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource. Use foundation/tags to produce a conformant map (ADR 0010)."
}

variable "address_space" {
  type        = list(string)
  description = "Hub VNet address space, CIDR notation. The VALUE is the adopter's — centrally assigned, non-overlapping, written down (ADR 0018: re-numbering a live network is the truest one-way door). No default on purpose."

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "address_space must be a non-empty list of valid CIDR blocks (e.g., ['10.0.0.0/22'])."
  }
}

variable "subnets" {
  type = map(object({
    address_prefixes = list(string)
  }))
  default     = {}
  description = "Subnets to carve from the hub address space, keyed by subnet name. Azure-mandated names (AzureFirewallSubnet, GatewaySubnet, AzureBastionSubnet) belong to the deferred v0.2 scope; v0.1 consumers typically declare a private-endpoints subnet."

  validation {
    condition     = alltrue([for k, s in var.subnets : alltrue([for cidr in s.address_prefixes : can(cidrhost(cidr, 0))])])
    error_message = "every subnet address prefix must be a valid CIDR block."
  }
}

variable "private_dns_zones" {
  type        = list(string)
  description = "Private DNS zones to create in the hub and link to the hub VNet (ADR 0018: centralized resolution). The default is exactly the set the shipped modules require: Key Vault private endpoints plus the five Azure Monitor / AMPLS zones."
  default = [
    "privatelink.vaultcore.azure.net",
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.blob.core.windows.net",
  ]

  validation {
    condition     = alltrue([for z in var.private_dns_zones : can(regex("^[a-z0-9.-]+$", z))])
    error_message = "private_dns_zones entries must be lowercase DNS zone names."
  }
}

variable "create_ampls" {
  type        = bool
  default     = true
  description = "Create the Azure Monitor Private Link Scope — the hard prerequisite the observability substrate's private-by-default posture documents. Disable only if the estate already operates an AMPLS elsewhere."
}

variable "ampls_name" {
  type        = string
  default     = null
  description = "Name for the AMPLS. Defaults to 'ampls-<virtual_network_name>' — foundation/naming has no AMPLS type yet; supply explicitly to override."
}

variable "ampls_linked_resource_ids" {
  type        = map(string)
  default     = {}
  description = "Azure Monitor resources to place inside the AMPLS, keyed by a short label (e.g. { law = <workspace id>, appi = <app insights id> }). Wire the observability substrate's outputs here — this is the seam that makes its private posture actually work."

  validation {
    condition     = alltrue([for k, id in var.ampls_linked_resource_ids : can(regex("^/subscriptions/", id))])
    error_message = "ampls_linked_resource_ids values must be full Azure resource IDs."
  }
}

variable "ampls_ingestion_access_mode" {
  type        = string
  default     = "PrivateOnly"
  description = "AMPLS ingestion access mode. 'PrivateOnly' (default, ADR 0018 default-deny posture) or 'Open' for estates mid-migration."

  validation {
    condition     = contains(["Open", "PrivateOnly"], var.ampls_ingestion_access_mode)
    error_message = "ampls_ingestion_access_mode must be one of: Open, PrivateOnly."
  }
}

variable "ampls_query_access_mode" {
  type        = string
  default     = "PrivateOnly"
  description = "AMPLS query access mode. 'PrivateOnly' (default) or 'Open'."

  validation {
    condition     = contains(["Open", "PrivateOnly"], var.ampls_query_access_mode)
    error_message = "ampls_query_access_mode must be one of: Open, PrivateOnly."
  }
}

variable "ampls_private_endpoint_subnet_key" {
  type        = string
  default     = null
  description = "Key into var.subnets naming the subnet that hosts the AMPLS private endpoint. Null skips the endpoint — valid only when the consumer wires it at a higher layer."
}

variable "ampls_private_endpoint_name" {
  type        = string
  default     = null
  description = "Name for the AMPLS private endpoint. Defaults to 'pep-ampls-<virtual_network_name>'. Compute via foundation/naming (private_endpoint) to override."
}
