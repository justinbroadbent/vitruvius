variable "name_prefix" {
  type        = string
  default     = "platform"
  description = "Prefix for the Azure resource names this module creates (policy definitions, initiative, assignment). Identifies platform-library artifacts in the estate; set it to your org short-code if you prefer. Kept short because management-group policy assignment names cap at 24 characters."

  validation {
    condition     = can(regex("^[a-z0-9](-?[a-z0-9])*$", var.name_prefix)) && length(var.name_prefix) >= 2 && length(var.name_prefix) <= 9
    error_message = "name_prefix must be 2-9 chars: lowercase alphanumeric with single interior hyphens."
  }
}

variable "policy_management_group_id" {
  type        = string
  default     = null
  description = "Management group resource ID where the guardrail policy definitions and initiative are created. When null, the module ships no resources — useful for environments not yet ready to enforce the baseline."

  validation {
    condition     = var.policy_management_group_id == null ? true : can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", var.policy_management_group_id))
    error_message = "policy_management_group_id must be a full management group resource ID ('/providers/Microsoft.Management/managementGroups/<name>'), not a bare name — a bare name passes plan and fails apply."
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
  description = "Enforcement mode at the assignment level. 'DoNotEnforce' for the Audit period (ADR 0008); 'Default' once promoted. Independent of the per-policy 'effect' — both must be set to fully enforce."

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "policy_enforcement_mode must be one of: Default, DoNotEnforce."
  }
}

variable "policy_effect" {
  type        = string
  default     = "Audit"
  description = "Effect for every guardrail in the initiative. 'Audit' (default per ADR 0008) reports violations but blocks nothing. 'Deny' blocks non-compliant resources at create/update. 'Disabled' for break-glass."

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.policy_effect)
    error_message = "policy_effect must be one of: Audit, Deny, Disabled."
  }
}

variable "allowed_locations" {
  type        = list(string)
  default     = ["eastus", "eastus2"]
  description = "Approved Azure regions for the allowed-locations guardrail. Resources created outside this list fail the guardrail. Must be non-empty when the module deploys."

  validation {
    condition     = alltrue([for l in var.allowed_locations : can(regex("^[a-z0-9]+$", l))])
    error_message = "allowed_locations entries must be lowercase Azure region names (e.g., 'eastus')."
  }
}
