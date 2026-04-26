mock_provider "azurerm" {
  # Synthetic IDs in real Azure resource ID shape so client-side validation in
  # the policy_set_definition's reference parsing accepts them.
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-uai"
      principal_id = "11111111-1111-1111-1111-111111111111"
      client_id    = "22222222-2222-2222-2222-222222222222"
      tenant_id    = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.KeyVault/vaults/mock-kv"
      vault_uri = "https://mock-kv.vault.azure.net/"
    }
  }
  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/mock-policy-definition"
    }
  }
  mock_resource "azurerm_policy_set_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock-policy-set"
    }
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock-assignment"
    }
  }
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "33333333-3333-3333-3333-333333333333"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      client_id       = "44444444-4444-4444-4444-444444444444"
      object_id       = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  user_assigned_identity_name = "id-wsx-memberapi-dev-eus-01"
  key_vault_name              = "kv-wsx-memberapi-dev-eus"
  resource_group_name         = "rg-memberapi-dev"
  location                    = "eastus"
  tags = {
    "owner"                = "member-services"
    "env"                  = "dev"
    "cost-center"          = "cc-2002"
    "data-classification"  = "internal"
    "business-criticality" = "tier-2"
  }
  aks_oidc_issuer_url               = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/"
  aks_namespace                     = "memberapi"
  aks_service_account_name          = "memberapi-sa"
  log_analytics_workspace_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  policy_definition_subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "federated_credential_subject_is_correctly_built" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.aks.subject == "system:serviceaccount:memberapi:memberapi-sa"
    error_message = "federated credential subject must follow system:serviceaccount:<ns>:<sa> shape"
  }

  assert {
    condition     = azurerm_federated_identity_credential.aks.issuer == "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/"
    error_message = "federated credential issuer must match the AKS OIDC issuer URL input"
  }

  assert {
    condition     = contains(azurerm_federated_identity_credential.aks.audience, "api://AzureADTokenExchange")
    error_message = "federated credential audience must include api://AzureADTokenExchange (Entra ID token exchange)"
  }
}

run "service_account_annotations_are_correct" {
  command = apply

  assert {
    condition     = output.service_account_annotations["azure.workload.identity/client-id"] == "22222222-2222-2222-2222-222222222222"
    error_message = "service_account_annotations must surface the UAI client ID under the workload-identity annotation key"
  }

  assert {
    condition     = output.service_account_annotations["azure.workload.identity/tenant-id"] == "33333333-3333-3333-3333-333333333333"
    error_message = "service_account_annotations must surface the tenant ID under the workload-identity annotation key"
  }
}

run "policy_initiative_bundles_all_three_kv_policies" {
  command = apply

  assert {
    condition     = length(azurerm_policy_set_definition.this.policy_definition_reference) == 3
    error_message = "initiative must bundle all three KV-hardening policies"
  }
}

run "policy_assignment_skipped_when_scope_null" {
  command = apply

  assert {
    condition     = output.policy_assignment_id == null
    error_message = "policy_assignment_id must be null when policy_assignment_scope is not supplied"
  }
}

run "policy_assignment_created_when_scope_supplied" {
  command = apply

  variables {
    policy_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.policy_assignment_id != null
    error_message = "policy_assignment_id must be non-null when policy_assignment_scope is supplied"
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this[0].enforce == false
    error_message = "default policy_enforcement_mode must produce enforce=false (DoNotEnforce/Audit-before-Deny per ADR 0008)"
  }
}

