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

run "rejects_non_naming_convention_name" {
  command = plan
  variables { name = "mycluster" }
  expect_failures = [var.name]
}

run "rejects_name_exceeding_max_length" {
  command = plan
  variables { name = "aks-this-cluster-name-is-far-too-long-to-be-a-valid-azure-aks-resource-name" }
  expect_failures = [var.name]
}

run "rejects_resource_group_name_in_place_of_id" {
  command = plan
  variables { resource_group_id = "rg-platform-prod" }
  expect_failures = [var.resource_group_id]
}

run "rejects_uppercase_location" {
  command = plan
  variables { location = "EastUS" }
  expect_failures = [var.location]
}

run "rejects_malformed_node_subnet_id" {
  command = plan
  variables { node_subnet_id = "snet-aks" }
  expect_failures = [var.node_subnet_id]
}

run "rejects_malformed_workspace_id" {
  command = plan
  variables { log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/x" }
  expect_failures = [var.log_analytics_workspace_id]
}

run "rejects_empty_admin_groups" {
  command = plan
  variables { admin_group_object_ids = [] }
  expect_failures = [var.admin_group_object_ids]
}

run "rejects_non_guid_admin_group" {
  command = plan
  variables { admin_group_object_ids = ["platform-admins"] }
  expect_failures = [var.admin_group_object_ids]
}

run "rejects_tags_missing_required_key" {
  command = plan
  variables {
    tags = {
      "owner"               = "platform-team"
      "env"                 = "prod"
      "cost-center"         = "cc-1000"
      "data-classification" = "internal"
      # business-criticality intentionally missing
    }
  }
  expect_failures = [var.tags]
}

run "rejects_invalid_kubernetes_version" {
  command = plan
  variables { kubernetes_version = "latest" }
  expect_failures = [var.kubernetes_version]
}

run "rejects_off_vocabulary_upgrade_channel" {
  command = plan
  variables { upgrade_channel = "weekly" }
  expect_failures = [var.upgrade_channel]
}

run "rejects_zero_node_count" {
  command = plan
  variables { system_node_pool = { node_count = 0 } }
  expect_failures = [var.system_node_pool]
}

run "rejects_invalid_os_disk_type" {
  command = plan
  variables { system_node_pool = { os_disk_type = "SSD" } }
  expect_failures = [var.system_node_pool]
}

run "rejects_off_vocabulary_network_policy" {
  command = plan
  variables { network = { network_policy = "none" } }
  expect_failures = [var.network]
}
