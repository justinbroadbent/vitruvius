# Every variable here is a platform-published fact: the platform team hands
# these values to the workload team at onboarding (output of the platform's
# own roots — never read from platform state, per ADR 0004/0017). Defaults
# are obviously-fake placeholders so the example validates standalone.

variable "org" {
  type        = string
  default     = "wsx"
  description = "Organization short code (illustrative). Supplied by the platform team; also used as the policy name_prefix."

  validation {
    condition     = can(regex("^[a-z0-9]{2,5}$", var.org))
    error_message = "org must be 2-5 lowercase alphanumeric characters."
  }
}

variable "env" {
  type        = string
  default     = "dev"
  description = "Environment this workload root deploys. One environment = one subscription = one state file (ADR 0017/0024)."

  validation {
    condition     = contains(["prod", "staging", "dev", "sandbox"], var.env)
    error_message = "env must be one of: prod, staging, dev, sandbox (ADR 0010 vocabulary)."
  }
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region, long form."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a lowercase Azure region name."
  }
}

variable "aks_oidc_issuer_url" {
  type        = string
  default     = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/"
  description = "OIDC issuer URL of the platform AKS cluster this workload runs on. Published by the platform team."
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-dev/providers/Microsoft.OperationalInsights/workspaces/log-wsx-platform-dev-eus-01"
  description = "Resource ID of the platform observability substrate's Log Analytics workspace (the observability-substrate module's log_analytics_workspace_id output)."
}

variable "private_endpoint_subnet_id" {
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-dev/providers/Microsoft.Network/virtualNetworks/vnet-spoke-dev/subnets/snet-private-endpoints"
  description = "Subnet where the Key Vault private endpoint lands. Published by the platform's networking layer (ADR 0018) — a networking/hub subnet_ids output, or the workload spoke's own."
}

variable "key_vault_dns_zone_id" {
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  description = "The hub's privatelink.vaultcore.azure.net private DNS zone — networking/hub's private_dns_zone_ids output. Centralized in the hub per ADR 0018."
}

variable "policy_assignment_scope" {
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000"
  description = "Scope where the workload's KV-hardening initiative is assigned — typically the team's environment subscription."
}
