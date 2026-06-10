mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

mock_provider "azapi" {}

variables {
  virtual_network_name = "vnet-wsx-hub-dev-eus-01"
  resource_group_name  = "rg-wsx-hub-dev-eus-01"
  location             = "eastus"
  address_space        = ["10.0.0.0/22"]
}

run "rejects_non_naming_convention_vnet_name" {
  command = plan

  variables {
    virtual_network_name = "myhubnetwork"
  }

  expect_failures = [var.virtual_network_name]
}

run "rejects_invalid_address_space" {
  command = plan

  variables {
    address_space = ["10.0.0.0/22", "not-a-cidr"]
  }

  expect_failures = [var.address_space]
}

run "rejects_empty_address_space" {
  command = plan

  variables {
    address_space = []
  }

  expect_failures = [var.address_space]
}

run "rejects_invalid_subnet_prefix" {
  command = plan

  variables {
    subnets = {
      private-endpoints = { address_prefixes = ["10.0.1.0/notmask"] }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_off_vocabulary_ingestion_mode" {
  command = plan

  variables {
    ampls_ingestion_access_mode = "Private"
  }

  expect_failures = [var.ampls_ingestion_access_mode]
}

run "rejects_off_vocabulary_query_mode" {
  command = plan

  variables {
    ampls_query_access_mode = "public"
  }

  expect_failures = [var.ampls_query_access_mode]
}

run "rejects_bare_linked_resource_id" {
  command = plan

  variables {
    ampls_linked_resource_ids = { law = "log-platform-dev" }
  }

  expect_failures = [var.ampls_linked_resource_ids]
}

run "rejects_endpoint_subnet_key_not_in_subnets" {
  command = plan

  variables {
    subnets = {
      private-endpoints = { address_prefixes = ["10.0.1.0/24"] }
    }
    ampls_private_endpoint_subnet_key = "missing-subnet"
  }

  expect_failures = [terraform_data.input_invariants]
}
