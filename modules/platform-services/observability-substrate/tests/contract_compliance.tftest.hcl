# Mocks the azurerm provider so the contract is verified without Azure
# credentials. Synthetic IDs use real Azure resource-ID shapes so the AVM
# modules' resource_id outputs resolve to something well-formed.
mock_provider "azurerm" {
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.OperationalInsights/workspaces/mock-law"
      workspace_id = "11111111-1111-1111-1111-111111111111"
    }
  }
  mock_resource "azurerm_application_insights" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/components/mock-appi"
      connection_string   = "InstrumentationKey=22222222-2222-2222-2222-222222222222"
      instrumentation_key = "22222222-2222-2222-2222-222222222222"
      app_id              = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/actionGroups/mock-ag"
    }
  }
  mock_resource "azurerm_monitor_activity_log_alert" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/activityLogAlerts/mock-alert"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  log_analytics_workspace_name = "log-wsx-platform-test-eus"
  application_insights_name    = "appi-wsx-platform-test-eus"
  resource_group_name          = "rg-platform-test"
  location                     = "eastus"
}

run "substrate_exposes_workspace_and_app_insights" {
  command = apply

  assert {
    condition     = output.log_analytics_workspace_id != null && output.log_analytics_workspace_id != ""
    error_message = "log_analytics_workspace_id must be exposed — it is the substrate input consumers depend on"
  }

  assert {
    condition     = output.application_insights_id != null && output.application_insights_id != ""
    error_message = "application_insights_id must be exposed"
  }

  assert {
    condition     = output.application_insights_connection_string != null
    error_message = "application_insights_connection_string must be exposed (the collector's exporter target)"
  }
}

run "no_action_group_without_receivers" {
  command = apply

  assert {
    condition     = output.action_group_id == null
    error_message = "action_group_id must be null when no alert_email_receivers are supplied"
  }

  assert {
    condition     = length(azurerm_monitor_action_group.platform) == 0
    error_message = "no action group should be created without receivers"
  }
}

run "substrate_deletion_alert_always_ships" {
  command = apply

  assert {
    condition     = azurerm_monitor_activity_log_alert.substrate_deletion.criteria[0].operation_name == "Microsoft.OperationalInsights/workspaces/delete"
    error_message = "the substrate must ship its own deletion alert (ADR 0008 §3)"
  }
}

run "action_group_created_and_wired_when_receivers_supplied" {
  command = apply

  variables {
    alert_email_receivers = [
      {
        name          = "platform-oncall"
        email_address = "oncall@example.org"
      },
    ]
  }

  assert {
    condition     = output.action_group_id != null
    error_message = "action_group_id must be non-null when receivers are supplied"
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.substrate_deletion.action) == 1
    error_message = "the deletion alert must wire to the action group when one exists"
  }
}
