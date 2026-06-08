variable "log_analytics_workspace_name" {
  type        = string
  description = "Name of the central Log Analytics workspace — the platform substrate. Produced by foundation/naming upstream, passed in here."

  validation {
    condition     = length(var.log_analytics_workspace_name) > 0
    error_message = "log_analytics_workspace_name must not be empty."
  }
}

variable "application_insights_name" {
  type        = string
  description = "Name of the workspace-based Application Insights component. Produced by foundation/naming upstream."

  validation {
    condition     = length(var.application_insights_name) > 0
    error_message = "application_insights_name must not be empty."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the substrate resources are created in. The consumer (environment root) owns and supplies the RG; this module does not create it (ADR 0004 / ADR 0024)."

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the substrate resources."

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

variable "log_analytics_retention_in_days" {
  type        = number
  default     = 30
  description = "Hot-tier retention for the workspace, in days. ADR 0005 reference default is 30 (hot); warm/cold tiering is configured separately. Per-environment tuning (dev 7 / staging 14 / prod tiered) is the consumer's call."

  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "log_analytics_retention_in_days must be between 30 and 730 (Azure Log Analytics limits)."
  }
}

variable "log_analytics_daily_quota_gb" {
  type        = number
  default     = null
  description = "Daily ingestion cap in GB — a cost guardrail against the telemetry-dumping-ground failure (AP-002). Null means no cap. Set a value in cost-sensitive environments."

  validation {
    condition     = var.log_analytics_daily_quota_gb == null ? true : var.log_analytics_daily_quota_gb > 0
    error_message = "log_analytics_daily_quota_gb must be greater than 0 when set, or null for no cap."
  }
}

variable "log_analytics_sku" {
  type        = string
  default     = "PerGB2018"
  description = "Log Analytics pricing SKU. PerGB2018 is the standard pay-as-you-go tier."

  validation {
    condition     = contains(["PerGB2018", "CapacityReservation", "Free", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "log_analytics_sku must be one of: PerGB2018, CapacityReservation, Free, Standard, Premium."
  }
}

variable "application_insights_retention_in_days" {
  type        = number
  default     = 90
  description = "Application Insights data retention, in days. Azure-supported values: 30, 60, 90, 120, 180, 270, 365, 550, 730."

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_in_days)
    error_message = "application_insights_retention_in_days must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730."
  }
}

variable "action_group_name" {
  type        = string
  default     = "vitruvius-platform"
  description = "Name of the platform action group that alerts route to. Only created when alert_email_receivers is non-empty."
}

variable "action_group_short_name" {
  type        = string
  default     = "vitruvius"
  description = "Short name for the action group (shown in SMS/email). Azure limits this to 12 characters."

  validation {
    condition     = length(var.action_group_short_name) > 0 && length(var.action_group_short_name) <= 12
    error_message = "action_group_short_name must be 1–12 characters (Azure limit)."
  }
}

variable "alert_email_receivers" {
  type = list(object({
    name          = string
    email_address = string
  }))
  default     = []
  description = "Email receivers for the platform action group. When empty, no action group is created and the substrate-deletion alert ships without an action wired (still visible in the portal). Owner-based routing (ADR 0010) is the consumer's to expand."
}
