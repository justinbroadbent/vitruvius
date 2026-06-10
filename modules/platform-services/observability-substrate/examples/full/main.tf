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

# Full substrate: tuned retention, a daily ingestion cap (AP-002 cost
# guardrail), and an action group wired to the platform on-call so the
# substrate-deletion alert (ADR 0008 §3) actually pages someone. Tags would
# come from foundation/tags (ADR 0010) in a real environment root.

module "observability_substrate" {
  source = "../.."

  log_analytics_workspace_name = "log-wsx-platform-prod-eus"
  application_insights_name    = "appi-wsx-platform-prod-eus"
  resource_group_name          = "rg-platform-prod"
  location                     = "eastus"

  log_analytics_retention_in_days        = 90
  log_analytics_daily_quota_gb           = 50
  application_insights_retention_in_days = 365

  action_group_name       = "platform-alerts-prod"
  action_group_short_name = "vitruprod"
  alert_email_receivers = [
    {
      name          = "platform-oncall"
      email_address = "platform-oncall@example.org"
    },
  ]

  tags = {
    owner                = "platform-team"
    env                  = "prod"
    cost-center          = "cc-0001"
    data-classification  = "internal"
    business-criticality = "tier-1"
  }
}

output "log_analytics_workspace_id" {
  value = module.observability_substrate.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  value     = module.observability_substrate.application_insights_connection_string
  sensitive = true
}

output "action_group_id" {
  value = module.observability_substrate.action_group_id
}
