terraform {
  # 1.14+ required: the AVM managed-cluster module pins required_version = "~> 1.14".
  required_version = ">= 1.14.0"

  required_providers {
    # The AVM managed-cluster module is azapi-based (the cluster itself is an
    # azapi_resource). Declared here so `terraform test` can bind a
    # mock_provider "azapi" block; the AVM module pins ~> 2.9.
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.9.0"
    }
    # Used by the AVM module for diagnostic settings; it pins >= 4.46, < 5.0.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.46.0"
    }
  }
}
