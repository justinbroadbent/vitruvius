variable "org" {
  type        = string
  default     = "wsx"
  description = "Organization short code (illustrative). 2–5 lowercase alphanumeric characters."
}

variable "env" {
  type        = string
  default     = "dev"
  description = "Environment for this landing zone. One of prod, staging, dev, sandbox."
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region in long form (e.g., eastus). Used both as the naming region and the resource-group location."
}

variable "platform_management_group_id" {
  type        = string
  default     = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  description = "Management group the substrate-routing initiative is created and assigned at (illustrative). In a real estate this is the ALZ platform management group (ADR 0024)."
}
