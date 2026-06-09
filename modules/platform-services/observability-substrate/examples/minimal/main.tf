terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# The substrate at its smallest: a workspace + workspace-based App Insights
# in an existing resource group, default 30-day retention, no cap, no alert
# routing. The consumer (environment root) owns the RG and supplies names
# from foundation/naming.

module "observability_substrate" {
  source = "../.."

  log_analytics_workspace_name = "log-wsx-platform-dev-eus"
  application_insights_name    = "appi-wsx-platform-dev-eus"
  resource_group_name          = "rg-platform-dev"
  location                     = "eastus"
}

output "log_analytics_workspace_id" {
  value = module.observability_substrate.log_analytics_workspace_id
}

output "application_insights_id" {
  value = module.observability_substrate.application_insights_id
}
