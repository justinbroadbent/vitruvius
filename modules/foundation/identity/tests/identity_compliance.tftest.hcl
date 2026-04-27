mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-uai"
      principal_id = "11111111-1111-1111-1111-111111111111"
      client_id    = "22222222-2222-2222-2222-222222222222"
      tenant_id    = "33333333-3333-3333-3333-333333333333"
    }
  }
}

variables {
  resource_group_name = "rg-platform-prod"
  location            = "eastus"
  tags = {
    "owner"                = "platform-team"
    "env"                  = "prod"
    "cost-center"          = "cc-1001"
    "data-classification"  = "internal"
    "business-criticality" = "tier-0"
  }
}

run "default_names_match_convention" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.deploy.name == "id-platform-deploy"
    error_message = "deploy UAI default name must be id-platform-deploy"
  }

  assert {
    condition     = azurerm_user_assigned_identity.policy_remediation.name == "id-platform-policy-remediation"
    error_message = "policy-remediation UAI default name must be id-platform-policy-remediation"
  }
}

run "tags_propagate_to_both_identities" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.deploy.tags["owner"] == "platform-team"
    error_message = "deploy UAI must carry the supplied tag map"
  }

  assert {
    condition     = azurerm_user_assigned_identity.policy_remediation.tags["business-criticality"] == "tier-0"
    error_message = "policy-remediation UAI must carry the supplied tag map"
  }
}

run "outputs_have_documented_shape" {
  command = apply

  assert {
    condition = (
      output.deploy.id != null &&
      output.deploy.principal_id != null &&
      output.deploy.client_id != null &&
      output.deploy.tenant_id != null &&
      output.deploy.name == "id-platform-deploy"
    )
    error_message = "deploy output must contain id, principal_id, client_id, tenant_id, and name"
  }

  assert {
    condition = (
      output.policy_remediation.id != null &&
      output.policy_remediation.principal_id != null &&
      output.policy_remediation.client_id != null &&
      output.policy_remediation.tenant_id != null &&
      output.policy_remediation.name == "id-platform-policy-remediation"
    )
    error_message = "policy_remediation output must contain id, principal_id, client_id, tenant_id, and name"
  }
}

run "name_overrides_are_honored" {
  command = plan

  variables {
    deploy_identity_name             = "id-platform-deploy-eastus2"
    policy_remediation_identity_name = "id-platform-policy-remediation-eastus2"
  }

  assert {
    condition     = azurerm_user_assigned_identity.deploy.name == "id-platform-deploy-eastus2"
    error_message = "deploy UAI name override must be honored"
  }

  assert {
    condition     = azurerm_user_assigned_identity.policy_remediation.name == "id-platform-policy-remediation-eastus2"
    error_message = "policy-remediation UAI name override must be honored"
  }
}

run "rejects_non_naming_convention_deploy_name" {
  command = plan

  variables {
    deploy_identity_name = "platform-deploy"
  }

  expect_failures = [var.deploy_identity_name]
}

run "rejects_non_naming_convention_policy_name" {
  command = plan

  variables {
    policy_remediation_identity_name = "policy-remediation"
  }

  expect_failures = [var.policy_remediation_identity_name]
}

run "rejects_tags_missing_required_key" {
  command = plan

  variables {
    tags = {
      "owner"               = "platform-team"
      "env"                 = "prod"
      "cost-center"         = "cc-1001"
      "data-classification" = "internal"
      # business-criticality intentionally missing
    }
  }

  expect_failures = [var.tags]
}

run "rejects_uppercase_location" {
  command = plan

  variables {
    location = "EastUS"
  }

  expect_failures = [var.location]
}
