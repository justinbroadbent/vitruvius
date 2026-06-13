terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.35.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Guardrail definitions and initiative created at the platform management
# group; no assignment. Use this shape when assignment happens in a separate
# rollout PR or at a higher organizational scope.

module "policy_baseline" {
  source = "../.."

  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  allowed_locations          = ["eastus", "eastus2"]
}

output "guardrail_policies" {
  value = module.policy_baseline.guardrail_policies
}

output "initiative_id" {
  value = module.policy_baseline.initiative_id
}
