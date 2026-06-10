terraform {
  required_version = ">= 1.7.0"
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

# Provisions both platform UAIs in the platform resource group with the
# canonical tag map. Default names are used (id-platform-deploy and
# id-platform-policy-remediation).

module "tags" {
  source = "../../../tags"

  owner                = "platform-team"
  env                  = "prod"
  cost_center          = "cc-1001"
  data_classification  = "internal"
  business_criticality = "tier-0"

  app = "platform"
}

module "identity" {
  source = "../.."

  resource_group_name = "rg-platform-prod"
  location            = "eastus"
  tags                = module.tags.tags
}

output "deploy_principal_id" {
  value = module.identity.deploy.principal_id
}

output "policy_remediation_id" {
  value = module.identity.policy_remediation.id
}
