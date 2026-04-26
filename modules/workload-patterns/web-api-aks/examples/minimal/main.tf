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

# Smallest viable invocation. Demonstrates the canonical composition:
# foundation/naming computes names; foundation/tags produces the tag map; the
# workload pattern consumes both. Policy initiative is created but not
# assigned (assignment is assumed to happen at a higher scope or in a separate
# rollout PR).

module "naming" {
  source = "../../../../foundation/naming"

  org      = "wsx"
  workload = "memberapi"
  env      = "dev"
  region   = "eastus"
}

module "tags" {
  source = "../../../../foundation/tags"

  owner                = "member-services"
  env                  = "dev"
  cost_center          = "cc-2002"
  data_classification  = "internal"
  business_criticality = "tier-2"

  app = "memberapi"
}

module "web_api" {
  source = "../.."

  user_assigned_identity_name = module.naming.names.managed_identity
  key_vault_name              = module.naming.names.key_vault
  resource_group_name         = "rg-memberapi-dev"
  location                    = "eastus"
  tags                        = module.tags.tags

  aks_oidc_issuer_url      = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/"
  aks_namespace            = "memberapi"
  aks_service_account_name = "memberapi-sa"

  log_analytics_workspace_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  policy_definition_subscription_id = "00000000-0000-0000-0000-000000000000"
}

output "service_account_annotations" {
  value = module.web_api.service_account_annotations
}
