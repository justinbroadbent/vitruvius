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

# Minimal hub: the VNet, the default private DNS zone set, and an AMPLS with
# nothing scoped into it yet. Address space is an obviously-fake placeholder —
# the real value is the adopter's addressing plan (ADR 0018).

module "hub" {
  source = "../.."

  virtual_network_name = "vnet-wsx-hub-dev-eus-01"
  resource_group_name  = "rg-wsx-hub-dev-eus-01"
  location             = "eastus"
  address_space        = ["10.0.0.0/22"]
}

output "private_dns_zone_ids" {
  value = module.hub.private_dns_zone_ids
}
