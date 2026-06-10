terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Full invocation: a private-endpoints subnet, the substrate's workspace and
# App Insights scoped into the AMPLS, and the AMPLS private endpoint wired
# through the Azure Monitor zones. All IDs are obviously-fake placeholders.

module "naming" {
  source = "../../../../foundation/naming"

  org      = "wsx"
  workload = "hub"
  env      = "prod"
  region   = "eastus"
}

module "hub" {
  source = "../.."

  virtual_network_name = module.naming.names.virtual_network
  resource_group_name  = "rg-wsx-hub-prod-eus-01"
  location             = "eastus"
  address_space        = ["10.0.0.0/22"]

  subnets = {
    private-endpoints = { address_prefixes = ["10.0.1.0/24"] }
  }

  ampls_linked_resource_ids = {
    law  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-wsx-platform-prod-eus-01"
    appi = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.Insights/components/appi-wsx-platform-prod-eus-01"
  }

  ampls_private_endpoint_subnet_key = "private-endpoints"
  ampls_private_endpoint_name       = module.naming.names.private_endpoint
  ampls_ingestion_access_mode       = "PrivateOnly"
  ampls_query_access_mode           = "PrivateOnly"
}

output "virtual_network_id" {
  value = module.hub.virtual_network_id
}

output "ampls_id" {
  value = module.hub.ampls_id
}

output "ampls_private_endpoint_id" {
  value = module.hub.ampls_private_endpoint_id
}
