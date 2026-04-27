# Platform-baseline user-assigned managed identities.
#
# This module ships only the identity primitives. Role assignments, custom
# role definitions, federated credentials, PIM eligibility, and Conditional
# Access are deliberately out of scope — see AGENTS.md for what's deferred
# and why.

resource "azurerm_user_assigned_identity" "deploy" {
  name                = var.deploy_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "policy_remediation" {
  name                = var.policy_remediation_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
