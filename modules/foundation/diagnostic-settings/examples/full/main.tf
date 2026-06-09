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

# Definitions, initiative, and assignment all deployed at the platform MG.
# Defaults to AuditIfNotExists + DoNotEnforce for the Audit period (ADR 0008).
# Promote to DeployIfNotExists + Default once the substrate-routing telemetry
# confirms no false positives.

module "diagnostic_settings" {
  source = "../.."

  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  policy_assignment_scope    = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"

  policy_effect              = "AuditIfNotExists"
  policy_enforcement_mode    = "DoNotEnforce"
  policy_assignment_location = "eastus"
}

output "covered_resource_types" {
  value = module.diagnostic_settings.covered_resource_types
}

output "initiative_id" {
  value = module.diagnostic_settings.initiative_id
}

output "assignment_id" {
  value = module.diagnostic_settings.assignment_id
}
