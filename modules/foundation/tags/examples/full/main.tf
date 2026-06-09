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

# Full invocation: produces the tag map AND deploys the tag-taxonomy initiative
# at a management group, with all optional tags supplied. Defaults to
# DoNotEnforce per ADR 0008 (Audit-before-Deny).

module "tags" {
  source = "../.."

  owner                = "member-services"
  env                  = "prod"
  cost_center          = "cc-2002"
  data_classification  = "confidential"
  business_criticality = "tier-1"

  app             = "memberapi"
  component       = "core"
  lifecycle_stage = "stable"

  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  policy_enforcement_mode    = "DoNotEnforce"
  policy_assignment_location = "eastus"
}

output "tags" {
  value = module.tags.tags
}

output "initiative_id" {
  value = module.tags.initiative_id
}

output "assignment_id" {
  value = module.tags.assignment_id
}
