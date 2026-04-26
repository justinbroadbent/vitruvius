variable "org" {
  type        = string
  description = "Organization short code. 2-5 lowercase alphanumeric characters."

  validation {
    condition     = can(regex("^[a-z0-9]{2,5}$", var.org))
    error_message = "org must be 2-5 lowercase alphanumeric characters."
  }
}

variable "workload" {
  type        = string
  description = "Workload alias matching a Backstage catalog component. 2-15 chars: lowercase alphanumeric or hyphens."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,15}$", var.workload))
    error_message = "workload must be 2-15 chars: lowercase alphanumeric or hyphens."
  }
}

variable "env" {
  type        = string
  description = "Environment. Must match the tag taxonomy in ADR 0010."

  validation {
    condition     = contains(["prod", "staging", "dev", "sandbox"], var.env)
    error_message = "env must be one of: prod, staging, dev, sandbox."
  }
}

variable "region" {
  type        = string
  description = "Azure region (long form, e.g., eastus). Mapped to a short code in the name."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.region))
    error_message = "region must be lowercase alphanumeric (e.g., 'eastus' not 'East US')."
  }
}

variable "instance" {
  type        = string
  default     = "01"
  description = "Two-digit instance suffix. Default 01."

  validation {
    condition     = can(regex("^[0-9]{2}$", var.instance))
    error_message = "instance must be a two-digit number (e.g., '01')."
  }
}
