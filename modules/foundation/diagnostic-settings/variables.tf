variable "policy_management_group_id" {
  type        = string
  default     = null
  description = "Management group resource ID where the diagnostic-settings policy definitions, initiative, and assignment are deployed. When null, the module ships no resources — useful for environments that aren't ready to enforce substrate routing yet."

  validation {
    condition     = var.policy_management_group_id == null ? true : can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", var.policy_management_group_id))
    error_message = "policy_management_group_id must be a full management group resource ID ('/providers/Microsoft.Management/managementGroups/<name>'), not a bare name — a bare name passes plan and fails apply."
  }
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Resource ID of the platform Log Analytics workspace that receives diagnostic logs from resources covered by the initiative. Required when policy_management_group_id is supplied."

  validation {
    # Case-insensitive GUID: some Azure APIs emit uppercase-hex subscription IDs.
    condition     = var.log_analytics_workspace_id == null ? true : can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a full Log Analytics workspace resource ID (/subscriptions/<guid>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>)."
  }
}

variable "policy_assignment_scope" {
  type        = string
  default     = null
  description = "Management group resource ID where the initiative is assigned. When null, definitions and the initiative are created at policy_management_group_id but no assignment is made — useful when assignment is handled by a higher-level config."

  validation {
    condition     = var.policy_assignment_scope == null ? true : can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", var.policy_assignment_scope))
    error_message = "policy_assignment_scope must be a full management group resource ID ('/providers/Microsoft.Management/managementGroups/<name>')."
  }
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
