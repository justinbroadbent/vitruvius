mock_provider "azurerm" {
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
  aks_oidc_issuer_url         = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/"
  aks_namespace               = "memberapi"
  aks_service_account_name    = "memberapi-sa"
  log_analytics_workspace_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  tags = {
    "owner"                = "member-services"
    "env"                  = "dev"
    "cost-center"          = "cc-2002"
    "data-classification"  = "internal"
    "business-criticality" = "tier-2"
  }
}

run "rejects_non_naming_convention_uai_name" {
  command = plan

  variables {
    user_assigned_identity_name = "myidentity"
  }

  expect_failures = [var.user_assigned_identity_name]
}

run "rejects_non_naming_convention_kv_name" {
  command = plan

  variables {
    key_vault_name = "mykv"
  }

  expect_failures = [var.key_vault_name]
}

run "rejects_kv_name_exceeding_24_chars" {
  command = plan

  variables {
    key_vault_name = "kv-this-name-is-way-too-long-for-azure-keyvault"
  }

  expect_failures = [var.key_vault_name]
}

run "rejects_off_vocabulary_kv_sku" {
  command = plan

  variables {
    key_vault_sku = "free"
  }

  expect_failures = [var.key_vault_sku]
}

run "rejects_soft_delete_retention_below_minimum" {
  command = plan

  variables {
    key_vault_soft_delete_retention_days = 1
  }

  expect_failures = [var.key_vault_soft_delete_retention_days]
}

run "rejects_soft_delete_retention_above_maximum" {
  command = plan

  variables {
    key_vault_soft_delete_retention_days = 365
  }

  expect_failures = [var.key_vault_soft_delete_retention_days]
}

run "rejects_non_https_oidc_issuer" {
  command = plan

  variables {
    aks_oidc_issuer_url = "http://insecure.example.com/"
  }

  expect_failures = [var.aks_oidc_issuer_url]
}

run "rejects_tags_missing_required_key" {
  command = plan

  variables {
    tags = {
      "owner"               = "member-services"
      "env"                 = "dev"
      "cost-center"         = "cc-2002"
      "data-classification" = "internal"
      # business-criticality intentionally missing
    }
  }

  expect_failures = [var.tags]
}

run "rejects_malformed_policy_assignment_scope" {
  command = plan

  variables {
    policy_assignment_scope = "not-a-scope"
  }

  expect_failures = [var.policy_assignment_scope]
}

run "accepts_resource_group_policy_assignment_scope" {
  command = plan

  variables {
    policy_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pilot"
  }

  # No expect_failures: a resource-group scope is a valid scope (ADR 0008 pilot path).
}

run "rejects_invalid_policy_enforcement_mode" {
  command = plan

  variables {
    policy_enforcement_mode = "Audit"
  }

  expect_failures = [var.policy_enforcement_mode]
}

run "rejects_kv_name_with_consecutive_hyphens" {
  command = plan

  variables {
    key_vault_name = "kv-member--api"
  }

  expect_failures = [var.key_vault_name]
}

run "rejects_kv_name_with_trailing_hyphen" {
  command = plan

  variables {
    key_vault_name = "kv-memberapi-"
  }

  expect_failures = [var.key_vault_name]
}

run "rejects_namespace_starting_with_hyphen" {
  command = plan

  variables {
    aks_namespace = "-memberapi"
  }

  expect_failures = [var.aks_namespace]
}

run "rejects_service_account_ending_with_hyphen" {
  command = plan

  variables {
    aks_service_account_name = "memberapi-sa-"
  }

  expect_failures = [var.aks_service_account_name]
}

run "rejects_oversized_federated_credential_name" {
  command = plan

  variables {
    aks_namespace            = "member-api-namespace-with-a-very-long-rfc1123-compliant-name1"
    aks_service_account_name = "member-api-service-account-with-very-long-rfc1123-compliant1"
  }

  expect_failures = [var.aks_service_account_name]
}
