variable "policy_management_group_id" {
  type        = string
  default     = null
  description = "Management group resource ID where the diagnostic-settings policy definitions, initiative, and assignment are deployed. When null, the module ships no resources — useful for environments that aren't ready to enforce substrate routing yet."
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Resource ID of the platform Log Analytics workspace that receives diagnostic logs from resources covered by the initiative. Required when policy_management_group_id is supplied."

  validation {
    condition     = var.log_analytics_workspace_id == null ? true : can(regex("^/subscriptions/[0-9a-f-]{36}/resourceGroups/", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a full Azure resource ID starting with /subscriptions/<guid>/resourceGroups/."
  }
}

variable "policy_assignment_scope" {
  type        = string
  default     = null
  description = "Management group resource ID where the initiative is assigned. When null, definitions and the initiative are created at policy_management_group_id but no assignment is made — useful when assignment is handled by a higher-level config."
}

variable "policy_enforcement_mode" {
  type        = string
  default     = "DoNotEnforce"
  description = "Enforcement mode at the assignment level. 'DoNotEnforce' for the Audit period (ADR 0008); 'Default' once promoted. Note: this controls whether the policy evaluates at all; the per-policy 'effect' parameter (Audit-vs-Deploy) is a separate dimension. Both must be flipped to fully enforce."

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "policy_enforcement_mode must be one of: Default, DoNotEnforce."
  }
}

variable "policy_effect" {
  type        = string
  default     = "AuditIfNotExists"
  description = "Effect for every policy in the initiative. 'AuditIfNotExists' (default per ADR 0008) reports drift but does not heal. 'DeployIfNotExists' deploys a diagnostic setting routing to the LAW. 'Disabled' for break-glass. Set per-policy tuning is not exposed in v0.1.0."

  validation {
    condition     = contains(["AuditIfNotExists", "DeployIfNotExists", "Disabled"], var.policy_effect)
    error_message = "policy_effect must be one of: AuditIfNotExists, DeployIfNotExists, Disabled."
  }
}

variable "policy_assignment_location" {
  type        = string
  default     = "eastus"
  description = "Region where the assignment's system-assigned managed identity resides. Required by Azure for DeployIfNotExists policies. Does not constrain where the policy applies."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.policy_assignment_location))
    error_message = "policy_assignment_location must be a lowercase Azure region name (e.g., 'eastus')."
  }
}
