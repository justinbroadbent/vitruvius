terraform {
  required_version = ">= 1.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.46.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Smallest viable cluster. foundation/naming computes the name; foundation/tags
# produces the tag map; the platform supplies the node subnet and the substrate
# workspace. The hardened posture (private, Entra RBAC, local accounts off, OIDC
# issuer + workload identity on) is applied by the module, not requested here.

module "naming" {
  source = "../../../../foundation/naming"

  org      = "wsx"
  workload = "platform"
  env      = "prod"
  region   = "eastus"
}

module "tags" {
  source = "../../../../foundation/tags"

  owner                = "platform-team"
  env                  = "prod"
  cost_center          = "cc-1000"
  data_classification  = "internal"
  business_criticality = "tier-1"

  app = "platform"
}

module "aks" {
  source = "../.."

  name                       = module.naming.names.aks_cluster
  resource_group_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod"
  location                   = "eastus"
  node_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-prod/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod/subnets/snet-aks"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  admin_group_object_ids     = ["11111111-1111-1111-1111-111111111111"]
  tags                       = module.tags.tags
}

# The seam: workloads federate into this issuer with no shared secret.
output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}
