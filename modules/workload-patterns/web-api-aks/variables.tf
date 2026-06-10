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
    # Azure KV rules: 3-24 chars, must end alphanumeric, no consecutive hyphens.
    condition     = can(regex("^kv(-[a-z0-9]+)+$", var.key_vault_name)) && length(var.key_vault_name) <= 24
    error_message = "key_vault_name must start with 'kv-' (foundation/naming convention), use single interior hyphens, end alphanumeric, and respect Azure's 24-char limit."
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
    # RFC 1123 label: start/end alphanumeric.
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.aks_namespace))
    error_message = "aks_namespace must be a valid Kubernetes namespace (RFC 1123 label: 1-63 chars, lowercase alphanumeric or hyphens, starts and ends alphanumeric)."
  }
}

variable "aks_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount the workload's pods authenticate as. Used to build the federated credential subject. The app team is responsible for creating the ServiceAccount with the matching annotations."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.aks_service_account_name))
    error_message = "aks_service_account_name must be a valid Kubernetes name (RFC 1123 label: 1-63 chars, lowercase alphanumeric or hyphens, starts and ends alphanumeric)."
  }

  validation {
    # The federated identity credential is named fic-aks-<namespace>-<sa>;
    # Azure caps credential names at 120 chars. Cross-variable validation
    # requires Terraform 1.9+, which this module already floors at.
    condition     = length("fic-aks-${var.aks_namespace}-${var.aks_service_account_name}") <= 120
    error_message = "aks_namespace plus aks_service_account_name is too long: the federated credential name 'fic-aks-<namespace>-<service-account>' must be at most 120 characters."
  }
}

# --- Observability input (consumer supplies the platform LAW) ---

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace receiving Key Vault diagnostic logs. Per ADR 0005, all platform observability flows through the substrate."
}

variable "private_endpoints" {
  type = map(object({
    subnet_resource_id            = string
    private_dns_zone_resource_ids = optional(set(string), [])
    name                          = optional(string)
    location                      = optional(string)
    resource_group_name           = optional(string)
  }))
  default     = {}
  description = "Private endpoints for the Key Vault, passed through to the AVM module. The vault ships with public network access disabled and default-Deny ACLs, so without at least one private endpoint the workload cannot reach it — empty is acceptable only when the consumer wires the endpoint at a higher layer. Subnet and private-DNS zone IDs come from the consumer's networking (ADR 0018)."
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

variable "name_prefix" {
  type        = string
  default     = "platform"
  description = "Prefix for the Azure policy resource names this module creates (definitions, initiative, assignment). Identifies platform-library artifacts in the estate; set it to your org short-code if you prefer."

  validation {
    condition     = can(regex("^[a-z0-9](-?[a-z0-9])*$", var.name_prefix)) && length(var.name_prefix) >= 2 && length(var.name_prefix) <= 9
    error_message = "name_prefix must be 2-9 chars: lowercase alphanumeric with single interior hyphens."
  }
}

variable "policy_assignment_scope" {
  type        = string
  default     = null
  description = "Resource ID of the scope where the KV-hardening initiative is assigned — either a subscription (`/subscriptions/{guid}`) or a resource group (`/subscriptions/{guid}/resourceGroups/{name}`). The value is used as the actual assignment scope. When null, the definitions and initiative are still created but no assignment is made — useful when assignment is handled by a higher-level config. Per ADR 0008 the assignment defaults to DoNotEnforce (Audit) at whichever scope is chosen."

  validation {
    condition     = var.policy_assignment_scope == null || can(regex("^/subscriptions/[0-9a-fA-F-]{36}(/resourceGroups/[^/]+)?$", var.policy_assignment_scope))
    error_message = "policy_assignment_scope must be a subscription ID ('/subscriptions/{guid}') or a resource group ID ('/subscriptions/{guid}/resourceGroups/{name}')."
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

variable "policy_effect" {
  type        = string
  default     = "Audit"
  description = "Initiative-wide effect for the purge-protection and RBAC member policies. Defaults to Audit per ADR 0008. Promote to Deny once Audit-mode evidence supports it. The diagnostic-settings member is AuditIfNotExists and unaffected."

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.policy_effect)
    error_message = "policy_effect must be one of: Audit, Deny, Disabled."
  }
}
