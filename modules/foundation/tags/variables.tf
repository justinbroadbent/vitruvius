variable "owner" {
  type        = string
  description = "Accountable team alias. Matches a Backstage catalog group, not a person name."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,40}$", var.owner))
    error_message = "owner must be a team alias: 2-40 chars, lowercase alphanumeric or hyphens."
  }
}

variable "env" {
  type        = string
  description = "Deployment environment. Vocabulary-controlled per ADR 0010."

  validation {
    condition     = contains(["prod", "staging", "dev", "sandbox"], var.env)
    error_message = "env must be one of: prod, staging, dev, sandbox."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost center for financial allocation. Format 'cc-' followed by 4 digits (e.g., cc-1001)."

  validation {
    condition     = can(regex("^cc-[0-9]{4}$", var.cost_center))
    error_message = "cost_center must match the form 'cc-NNNN' (e.g., cc-1001)."
  }
}

variable "data_classification" {
  type        = string
  description = "Data sensitivity tier. Vocabulary-controlled per ADR 0010. Drives CMK, private-endpoint, and retention defaults downstream."

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted."
  }
}

variable "business_criticality" {
  type        = string
  description = "Recovery priority tier. Vocabulary-controlled per ADR 0010. Drives SLA, geo-redundancy, and PIM-only change-path defaults downstream."

  validation {
    condition     = contains(["tier-0", "tier-1", "tier-2", "tier-3"], var.business_criticality)
    error_message = "business_criticality must be one of: tier-0, tier-1, tier-2, tier-3."
  }
}

variable "app" {
  type        = string
  default     = null
  description = "Optional application alias. Should match a Backstage catalog component."

  validation {
    condition     = var.app == null ? true : can(regex("^[a-z0-9-]{2,40}$", var.app))
    error_message = "app must be 2-40 chars, lowercase alphanumeric or hyphens."
  }
}

variable "component" {
  type        = string
  default     = null
  description = "Optional sub-component name within an app."

  validation {
    condition     = var.component == null ? true : can(regex("^[a-z0-9-]{2,40}$", var.component))
    error_message = "component must be 2-40 chars, lowercase alphanumeric or hyphens."
  }
}

variable "lifecycle_stage" {
  type        = string
  default     = null
  description = "Optional lifecycle stage. Vocabulary-controlled per ADR 0010. Named 'lifecycle_stage' in Terraform inputs to avoid shadowing the lifecycle meta-argument; emitted as the 'lifecycle' tag key."

  validation {
    condition     = var.lifecycle_stage == null ? true : contains(["stable", "experimental", "deprecated"], var.lifecycle_stage)
    error_message = "lifecycle_stage must be one of: stable, experimental, deprecated (or null)."
  }
}

variable "policy_management_group_id" {
  type        = string
  default     = null
  description = "Management group resource ID where the tag policy definitions, initiative, and assignment are deployed. When null, the module produces only the tag map and ships no policy resources. Per ADR 0008, the assignment is created in Audit enforcement mode by default."
}

variable "policy_enforcement_mode" {
  type        = string
  default     = "DoNotEnforce"
  description = "Enforcement mode at the Azure Policy assignment level. 'DoNotEnforce' starts the assignment in evaluation-only mode (Audit-before-Deny per ADR 0008). Set to 'Default' once Audit-mode evidence supports promotion."

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "policy_enforcement_mode must be one of: Default, DoNotEnforce."
  }
}

variable "policy_assignment_location" {
  type        = string
  default     = "eastus"
  description = "Region where the assignment's system-assigned managed identity resides. Required when any included policy uses the 'modify' effect (the inherit-tag policy does). Does not constrain where the policy applies."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.policy_assignment_location))
    error_message = "policy_assignment_location must be a lowercase Azure region name (e.g., 'eastus')."
  }
}
