terraform {
  # 1.7+ required for `mock_provider` in `terraform test`. Tests in this module
  # mock the azurerm provider so they run without Azure credentials.
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.35+ required: azurerm_management_group_policy_set_definition was
      # introduced in 4.35.0.
      version = ">= 4.35.0"
    }
  }
}
