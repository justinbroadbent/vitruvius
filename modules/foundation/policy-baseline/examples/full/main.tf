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

# Guardrail definitions, initiative, and assignment all at the platform MG.
# Defaults to Audit + DoNotEnforce for the Audit period (ADR 0008). Promote to
# Deny + Default once Audit-mode evidence confirms no false positives — every
# subscription beneath the MG then inherits the enforced guardrails.

module "policy_baseline" {
  source = "../.."

  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/wsx-platform"
  policy_assignment_scope    = "/providers/Microsoft.Management/managementGroups/wsx-platform"

  allowed_locations       = ["eastus", "eastus2"]
  policy_effect           = "Audit"
  policy_enforcement_mode = "DoNotEnforce"
}

output "guardrail_policies" {
  value = module.policy_baseline.guardrail_policies
}

output "initiative_id" {
  value = module.policy_baseline.initiative_id
}

output "assignment_id" {
  value = module.policy_baseline.assignment_id
}
