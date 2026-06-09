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
