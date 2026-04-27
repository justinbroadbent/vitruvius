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

# Definitions and initiative created at the platform management group; no
# assignment. Use this shape when initiative assignment happens at a higher
# (organizational) scope or in a separate rollout PR.

module "diagnostic_settings" {
  source = "../.."

  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
}

output "covered_resource_types" {
  value = module.diagnostic_settings.covered_resource_types
}

output "initiative_id" {
  value = module.diagnostic_settings.initiative_id
}
