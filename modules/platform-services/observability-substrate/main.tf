locals {
  create_action_group = length(var.alert_email_receivers) > 0

  action_group_name       = coalesce(var.action_group_name, "${var.name_prefix}-alerts")
  action_group_short_name = coalesce(var.action_group_short_name, substr(var.name_prefix, 0, 12))
}

# The central Log Analytics workspace — the substrate every module's
# diagnostic settings and the OTel collector's Azure Monitor exporter route
# to (ADR 0005). Anchored on AVM per ADR 0001. Internet ingestion/query are
# set explicitly (not left to AVM defaults — the LAW and App Insights AVM
# modules default in opposite directions), consistent with the private-by-
# default posture of ADR 0018. Private operation requires an Azure Monitor
# Private Link Scope (AMPLS) the consumer provides — see the README.
module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = var.log_analytics_workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  enable_telemetry    = false

  log_analytics_workspace_sku                        = var.log_analytics_sku
  log_analytics_workspace_retention_in_days          = var.log_analytics_retention_in_days
  log_analytics_workspace_daily_quota_gb             = var.log_analytics_daily_quota_gb
  log_analytics_workspace_internet_ingestion_enabled = var.internet_ingestion_enabled
  log_analytics_workspace_internet_query_enabled     = var.internet_query_enabled
}

# Workspace-based Application Insights — the default exporter target for the
# collector and the APM surface workload patterns consume (ADR 0005).
module "application_insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.4.0"

  name                = var.application_insights_name
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = module.log_analytics_workspace.resource_id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_in_days
  tags                = var.tags
  enable_telemetry    = false

  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled
}

# Alert-routing infrastructure. Created only when receivers are supplied;
# owner-based fan-out (ADR 0010) is expanded by the consumer.
resource "azurerm_monitor_action_group" "platform" {
  count = local.create_action_group ? 1 : 0

  name                = local.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = local.action_group_short_name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = true
    }
  }
}

data "azurerm_subscription" "current" {}

# The substrate is not a fair target for experimentation (ADR 0008 §3): the
# module ships its own guard. An activity-log alert fires when someone
# attempts to delete the workspace, routed to the platform action group.
resource "azurerm_monitor_activity_log_alert" "substrate_deletion" {
  name                = "${var.name_prefix}-substrate-deletion"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alerts on attempted deletion of the platform Log Analytics workspace. The substrate protects itself (ADR 0008 §3)."
  tags                = var.tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.OperationalInsights/workspaces/delete"
    resource_id    = module.log_analytics_workspace.resource_id
  }

  dynamic "action" {
    for_each = local.create_action_group ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.platform[0].id
    }
  }
}
