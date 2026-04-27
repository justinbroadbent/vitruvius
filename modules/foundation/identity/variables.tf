variable "resource_group_name" {
  type        = string
  description = "Resource group where the platform's user-assigned managed identities are created. Must already exist."
}

variable "location" {
  type        = string
  description = "Azure region for the platform UAIs. The UAIs themselves are region-bound but their tokens work globally."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a lowercase Azure region name (e.g., 'eastus')."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tag map produced by the foundation/tags module. The five required keys from ADR 0010 must be present."

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

variable "deploy_identity_name" {
  type        = string
  default     = "id-platform-deploy"
  description = "Name for the platform's deploy UAI. The identity CI/CD assumes when applying platform Terraform. Override only when the foundation/naming convention demands it."

  validation {
    condition     = can(regex("^id-[a-z0-9-]{3,124}$", var.deploy_identity_name))
    error_message = "deploy_identity_name must start with 'id-' (foundation/naming convention)."
  }
}

variable "policy_remediation_identity_name" {
  type        = string
  default     = "id-platform-policy-remediation"
  description = "Name for the platform's policy-remediation UAI. Available as a centralized identity for Azure Policy assignments using DeployIfNotExists or Modify effects, in place of per-assignment SystemAssigned identities."

  validation {
    condition     = can(regex("^id-[a-z0-9-]{3,124}$", var.policy_remediation_identity_name))
    error_message = "policy_remediation_identity_name must start with 'id-' (foundation/naming convention)."
  }
}
