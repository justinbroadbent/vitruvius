# --- Identity inputs (consumer supplies pre-computed names per ADR 0004) ---

variable "user_assigned_identity_name" {
  type        = string
  description = "Name for the workload's user-assigned managed identity. Compute via foundation/naming and pass in."

  validation {
    condition     = can(regex("^id-[a-z0-9-]{3,124}$", var.user_assigned_identity_name))
    error_message = "user_assigned_identity_name must start with 'id-' (foundation/naming convention)."
  }
}

variable "key_vault_name" {
  type        = string
  description = "Name for the workload's Key Vault. Compute via foundation/naming and pass in. Subject to Azure's 3-24 char global-uniqueness constraints."

  validation {
    condition     = can(regex("^kv-[a-z0-9-]{3,21}$", var.key_vault_name))
    error_message = "key_vault_name must start with 'kv-' (foundation/naming convention) and respect Azure's 24-char limit."
  }
}

# --- Placement inputs ---

variable "resource_group_name" {
  type        = string
  description = "Resource group where the workload's UAI and Key Vault are created."
}

variable "location" {
  type        = string
  description = "Azure region for the workload's resources."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a lowercase Azure region name (e.g., 'eastus')."
  }
}

# --- Tagging input (consumer supplies via foundation/tags per ADR 0010) ---

variable "tags" {
  type        = map(string)
  description = "Tag map produced by the foundation/tags module. Required tags are validated by Azure Policy at the assignment scope, not by this module."

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

# --- AKS workload-identity federation inputs ---

variable "aks_oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the AKS cluster the workload runs on. Read from azurerm_kubernetes_cluster.this.oidc_issuer_url and pass in. Required for federated identity credential."

  validation {
    condition     = can(regex("^https://", var.aks_oidc_issuer_url))
    error_message = "aks_oidc_issuer_url must be an https:// URL."
  }
}

variable "aks_namespace" {
  type        = string
  description = "Kubernetes namespace where the workload's pods run. Used to build the federated credential subject."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}$", var.aks_namespace))
    error_message = "aks_namespace must be a valid Kubernetes namespace (1-63 chars, lowercase alphanumeric or hyphens)."
  }
}

variable "aks_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount the workload's pods authenticate as. Used to build the federated credential subject. The app team is responsible for creating the ServiceAccount with the matching annotations."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}$", var.aks_service_account_name))
    error_message = "aks_service_account_name must be a valid Kubernetes name (1-63 chars, lowercase alphanumeric or hyphens)."
  }
}

# --- Observability input (consumer supplies the platform LAW) ---

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace receiving Key Vault diagnostic logs. Per ADR 0005, all platform observability flows through the substrate."
}

# --- Key Vault tunables ---

variable "key_vault_sku" {
  type        = string
  default     = "standard"
  description = "Key Vault SKU. Default 'standard'; use 'premium' only when HSM-backed keys are a requirement."

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "key_vault_sku must be one of: standard, premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  type        = number
  default     = 90
  description = "Soft-delete retention window. Default 90 (max). Lowering is allowed but discouraged; auditors expect the maximum."

  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "key_vault_soft_delete_retention_days must be between 7 and 90."
  }
}

# --- Policy assignment ---

variable "policy_assignment_scope" {
  type        = string
  default     = null
  description = "Resource ID of the scope (subscription or resource group) where this module's policy initiative is assigned. When null, definitions and the initiative are created at subscription scope, but no assignment is made — useful when assignment is handled by a higher-level config."
}

variable "policy_definition_subscription_id" {
  type        = string
  description = "Subscription ID where the policy definitions and initiative are created. Definitions live at subscription scope; assignment can target the same subscription or a child resource group."

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.policy_definition_subscription_id))
    error_message = "policy_definition_subscription_id must be a valid GUID."
  }
}

variable "policy_enforcement_mode" {
  type        = string
  default     = "DoNotEnforce"
  description = "Enforcement mode at the assignment level. 'DoNotEnforce' for the Audit period (ADR 0008); 'Default' once promoted."

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "policy_enforcement_mode must be one of: Default, DoNotEnforce."
  }
}
