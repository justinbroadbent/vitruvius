terraform {
  # 1.7+ required for `mock_provider` in `terraform test`. Tests in this module
  # mock the azurerm provider so they run without Azure credentials.
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }
}
