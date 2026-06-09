terraform {
  # 1.9+ required because the AVM Key Vault module's submodules pin
  # required_version = ">= 1.9, < 2.0".
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.0+ required: azurerm_federated_identity_credential's
      # user_assigned_identity_id argument does not exist in 3.x.
      version = ">= 4.0.0"
    }
  }
}
