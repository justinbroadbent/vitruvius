# Contract tests run with mocked providers (no Azure credentials). Apply-time
# Azure constraints are out of scope here — CI proves the contract and the
# wiring, not a live deployment.

# The azurerm provider parses several cross-resource references as typed
# Azure IDs even under mocks, so the mock defaults must be ID-shaped: the
# DNS link parses the vnet ID, the private endpoint parses the subnet and
# AMPLS IDs.
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/privateDnsZones/mock.zone"
    }
  }
  mock_resource "azurerm_monitor_private_link_scope" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/privateLinkScopes/ampls-mock"
    }
  }
}

# azapi backs the AVM virtualnetwork module. Default every azapi resource to
# a subnet-shaped ID (covers all subnets); the single vnet resource is
# overridden below with a vnet-shaped ID for the DNS links to parse.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/snet-mock"
    }
  }
}

override_resource {
  target = module.virtual_network.azapi_resource.vnet
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock"
  }
}

variables {
  virtual_network_name = "vnet-wsx-hub-dev-eus-01"
  resource_group_name  = "rg-wsx-hub-dev-eus-01"
  location             = "eastus"
  address_space        = ["10.0.0.0/22"]
  subnets = {
    private-endpoints = { address_prefixes = ["10.0.1.0/24"] }
  }
  ampls_linked_resource_ids = {
    law  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-platform"
    appi = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.Insights/components/appi-platform"
  }
  ampls_private_endpoint_subnet_key = "private-endpoints"
}

run "default_zone_set_covers_shipped_modules" {
  command = apply

  # Key Vault private endpoints + the five Azure Monitor / AMPLS zones.
  assert {
    condition     = length(module.private_dns_zones) == 6
    error_message = "default private_dns_zones must create the six zones the shipped modules require"
  }

  assert {
    condition     = contains(keys(module.private_dns_zones), "privatelink.vaultcore.azure.net")
    error_message = "the Key Vault private-link zone must be in the default set"
  }

  assert {
    condition     = length(output.private_dns_zone_ids) == 6
    error_message = "private_dns_zone_ids output must expose every zone"
  }
}

run "ampls_links_the_supplied_monitor_resources" {
  command = apply

  assert {
    condition     = length(azurerm_monitor_private_link_scoped_service.this) == 2
    error_message = "every entry in ampls_linked_resource_ids must become a scoped service"
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.this[0].ingestion_access_mode == "PrivateOnly" && azurerm_monitor_private_link_scope.this[0].query_access_mode == "PrivateOnly"
    error_message = "AMPLS must default to PrivateOnly access modes (ADR 0018 default-deny posture)"
  }

  assert {
    condition     = output.ampls_id != null
    error_message = "ampls_id output must be set when the AMPLS is created"
  }
}

run "ampls_private_endpoint_wires_monitor_zones" {
  command = apply

  assert {
    condition     = length(azurerm_private_endpoint.ampls) == 1
    error_message = "naming an endpoint subnet must create the AMPLS private endpoint"
  }

  assert {
    condition     = length(azurerm_private_endpoint.ampls[0].private_dns_zone_group[0].private_dns_zone_ids) == 5
    error_message = "the endpoint's DNS zone group must wire the five Azure Monitor zones"
  }

  assert {
    condition     = output.subnet_ids["private-endpoints"] != null
    error_message = "subnet_ids output must expose the endpoint subnet"
  }
}

run "ampls_can_be_disabled_for_estates_that_own_one" {
  command = apply

  variables {
    create_ampls                      = false
    ampls_private_endpoint_subnet_key = null
  }

  assert {
    condition     = length(azurerm_monitor_private_link_scope.this) == 0 && length(azurerm_monitor_private_link_scoped_service.this) == 0 && length(azurerm_private_endpoint.ampls) == 0
    error_message = "create_ampls = false must suppress the AMPLS, its scoped services, and the endpoint"
  }

  assert {
    condition     = output.ampls_id == null && output.ampls_private_endpoint_id == null
    error_message = "AMPLS outputs must be null when the AMPLS is not created"
  }
}

run "endpoint_skipped_without_subnet_key" {
  command = apply

  variables {
    ampls_private_endpoint_subnet_key = null
  }

  assert {
    condition     = length(azurerm_private_endpoint.ampls) == 0 && output.ampls_private_endpoint_id == null
    error_message = "no endpoint subnet key must mean no private endpoint"
  }
}
