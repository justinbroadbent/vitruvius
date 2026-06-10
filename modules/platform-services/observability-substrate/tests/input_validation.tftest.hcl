mock_provider "azurerm" {
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.OperationalInsights/workspaces/mock-law"
    }
  }
  mock_resource "azurerm_application_insights" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/components/mock-appi"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  log_analytics_workspace_name = "log-test"
  application_insights_name    = "appi-test"
  resource_group_name          = "rg-test"
  location                     = "eastus"
}

run "valid_minimal_inputs_succeed" {
  command = plan
}

run "rejects_retention_below_floor" {
  command = plan

  variables {
    log_analytics_retention_in_days = 7
  }

  expect_failures = [var.log_analytics_retention_in_days]
}

run "rejects_unsupported_app_insights_retention" {
  command = plan

  variables {
    application_insights_retention_in_days = 45
  }

  expect_failures = [var.application_insights_retention_in_days]
}

run "rejects_long_action_group_short_name" {
  command = plan

  variables {
    action_group_short_name = "this-is-way-too-long"
  }

  expect_failures = [var.action_group_short_name]
}

run "rejects_uppercase_location" {
  command = plan

  variables {
    location = "EastUS"
  }

  expect_failures = [var.location]
}

run "rejects_zero_daily_quota" {
  command = plan

  variables {
    log_analytics_daily_quota_gb = 0
  }

  expect_failures = [var.log_analytics_daily_quota_gb]
}

run "rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Platform"
  }

  expect_failures = [var.name_prefix]
}
