terraform {
  # 1.9+ required: the AVM modules this composes pin required_version >= 1.9, < 2.0.
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }
}
