terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Full invocation: every optional input supplied, policy initiative assigned
# at the subscription in DoNotEnforce mode (Audit-before-Deny per ADR 0008).
# Premium SKU and minimum soft-delete retention are atypical choices included
# here only to exercise the input surface.

module "naming" {
  source = "../../../../foundation/naming"

  org      = "wsx"
  workload = "memberapi"
  env      = "prod"
  region   = "eastus"
}

module "tags" {
  source = "../../../../foundation/tags"

  owner                = "member-services"
  env                  = "prod"
  cost_center          = "cc-2002"
  data_classification  = "confidential"
  business_criticality = "tier-1"

  app             = "memberapi"
  component       = "core"
  lifecycle_stage = "stable"
}

module "web_api" {
  source = "../.."

  user_assigned_identity_name = module.naming.names.managed_identity
  key_vault_name              = module.naming.names.key_vault
  resource_group_name         = "rg-memberapi-prod"
  location                    = "eastus"
  tags                        = module.tags.tags

  aks_oidc_issuer_url      = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/"
  aks_namespace            = "memberapi"
  aks_service_account_name = "memberapi-sa"

  log_analytics_workspace_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  key_vault_sku                        = "premium"
  key_vault_soft_delete_retention_days = 30

  policy_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  policy_enforcement_mode = "DoNotEnforce"
}

output "workload_identity_client_id" {
  value = module.web_api.workload_identity_client_id
}

output "key_vault_uri" {
  value = module.web_api.key_vault_uri
}

output "policy_assignment_id" {
  value = module.web_api.policy_assignment_id
}
