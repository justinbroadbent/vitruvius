variable "org" {
  type        = string
  default     = "wsx"
  description = "Organization short code (illustrative). 2–5 lowercase alphanumeric characters."

  validation {
    condition     = can(regex("^[a-z0-9]{2,5}$", var.org))
    error_message = "org must be 2-5 lowercase alphanumeric characters."
  }
}

variable "env" {
  type        = string
  default     = "dev"
  description = "Environment for this landing zone. One of prod, staging, dev, sandbox."

  validation {
    condition     = contains(["prod", "staging", "dev", "sandbox"], var.env)
    error_message = "env must be one of: prod, staging, dev, sandbox (ADR 0010 vocabulary)."
  }
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region in long form (e.g., eastus). Used both as the naming region and the resource-group location."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a lowercase Azure region name (e.g., 'eastus' not 'East US')."
  }
}

variable "platform_management_group_id" {
  type        = string
  default     = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  description = "Management group the substrate-routing initiative is created and assigned at (illustrative). In a real estate this is the ALZ platform management group (ADR 0024)."

  validation {
    condition     = can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", var.platform_management_group_id))
    error_message = "platform_management_group_id must be a full management group resource ID ('/providers/Microsoft.Management/managementGroups/<name>')."
  }
}

variable "hub_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/22"]
  description = "Hub VNet address space (illustrative). In a real estate this comes from the central, non-overlapping addressing plan (ADR 0018) — the discipline is decided, the numbers are yours."

  validation {
    condition     = length(var.hub_address_space) > 0 && alltrue([for cidr in var.hub_address_space : can(cidrhost(cidr, 0))])
    error_message = "hub_address_space must be a non-empty list of valid CIDR blocks."
  }
}

variable "hub_private_endpoint_prefixes" {
  type        = list(string)
  default     = ["10.0.1.0/24"]
  description = "Address prefixes for the hub's private-endpoints subnet (illustrative; must sit inside hub_address_space)."

  validation {
    condition     = alltrue([for cidr in var.hub_private_endpoint_prefixes : can(cidrhost(cidr, 0))])
    error_message = "hub_private_endpoint_prefixes must be valid CIDR blocks."
  }
}
