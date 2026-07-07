# Hermetic (no Azure): mock_provider supplies values for the wrapped AVM module's
# computed attributes so the documented outputs resolve.
#
# The AVM managed-cluster module is azapi-based, so azapi must be mocked too.
# The azapi mock needs realistic defaults: the provider's auto-generated mock ids
# are not valid Azure resource IDs, and downstream resources (the diagnostic
# setting, the default-agent-pool update) reject them. Likewise the kubeconfig
# action must return a decodable kubeconfig or the AVM module's own outputs error.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.ContainerService/managedClusters/aks-wsx-platform-prod-eus"
      output = {
        properties = {
          oidcIssuerProfile = { issuerURL = "https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/" }
          nodeResourceGroup = "MC_rg-platform-prod_aks-wsx-platform-prod-eus_eastus"
          identityProfile   = { kubeletidentity = { clientId = "c", objectId = "o", resourceId = "r" } }
        }
      }
    }
  }
  mock_resource "azapi_resource_action" {
    defaults = {
      # base64 of a minimal-but-parseable kubeconfig (kind: Config with one
      # cluster/user/context) — the AVM module base64decodes and yamldecodes it.
      output = { kubeconfigs = [{ value = "a2luZDogQ29uZmlnCmNsdXN0ZXJzOgotIG5hbWU6IGMKICBjbHVzdGVyOgogICAgY2VydGlmaWNhdGUtYXV0aG9yaXR5LWRhdGE6IGRHVnpkQT09CiAgICBzZXJ2ZXI6IGh0dHBzOi8veAp1c2VyczoKLSBuYW1lOiB1CiAgdXNlcjoKICAgIGNsaWVudC1jZXJ0aWZpY2F0ZS1kYXRhOiBkR1Z6ZEE9PQogICAgY2xpZW50LWtleS1kYXRhOiBkR1Z6ZEE9PQogICAgdG9rZW46IHQKY29udGV4dHM6Ci0gbmFtZTogY3R4CiAgY29udGV4dDoKICAgIGNsdXN0ZXI6IGMKICAgIHVzZXI6IHUK" }] }
    }
  }
}

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
  name                       = "aks-wsx-platform-prod-eus"
  resource_group_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod"
  location                   = "eastus"
  node_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-prod/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod/subnets/snet-aks"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform-prod/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod"
  admin_group_object_ids     = ["11111111-1111-1111-1111-111111111111"]
  tags = {
    "owner"                = "platform-team"
    "env"                  = "prod"
    "cost-center"          = "cc-1000"
    "data-classification"  = "internal"
    "business-criticality" = "tier-1"
  }
}

run "hardened_cluster_applies_and_surfaces_outputs" {
  command = apply

  assert {
    condition     = output.oidc_issuer_url != null && output.oidc_issuer_url != ""
    error_message = "the cluster must surface its OIDC issuer URL — the seam workloads federate into"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "the cluster must surface its resource ID"
  }

  assert {
    condition     = output.cluster_name != null
    error_message = "the cluster must surface its name"
  }

  assert {
    condition     = output.node_resource_group_name != null
    error_message = "the cluster must surface its node resource group"
  }

  assert {
    condition     = output.kubelet_identity != null
    error_message = "the cluster must surface its kubelet identity for downstream grants"
  }
}
