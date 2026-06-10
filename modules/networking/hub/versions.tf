terraform {
  # 1.9+ required: the AVM modules this composes pin required_version >= 1.9, < 2.0.
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
    # Declared at the root even though only the AVM virtualnetwork module
    # uses it: terraform test's mock_provider can only bind to providers the
    # root declares, and the tests must run without Azure credentials.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
  }
}
