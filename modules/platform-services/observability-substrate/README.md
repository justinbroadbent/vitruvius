# platform-services/observability-substrate

The central observability substrate: a Log Analytics workspace, a workspace-based Application Insights component, and platform alert-routing. This is the **target** every other module already assumes exists — `foundation/diagnostic-settings` and `web-api-aks` both take a `log_analytics_workspace_id` as input; this module is what produces it.

It is the implementation side of [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md): **all platform observability flows through one substrate.** The OpenTelemetry collector (ADR 0005 §1) exports to the Application Insights / Log Analytics this module provisions; services emit OTLP to the collector, never to a backend SDK directly. The collector deployment itself is host-dependent (it runs on the platform's compute) and is **out of this module's scope** — this module is the substrate the collector writes to.

## What it provisions

| Resource | Via | Why |
|---|---|---|
| Log Analytics workspace | AVM `avm-res-operationalinsights-workspace` | The hot-tier substrate. Internet ingestion/query set explicitly off by default (private-by-default, ADR 0018). |
| Application Insights (workspace-based) | AVM `avm-res-insights-component` | The default exporter target and APM surface workload patterns consume. Internet ingestion/query also off by default — the AVM module defaults them **on**, so this module sets them explicitly. |
| Action group | `azurerm_monitor_action_group` | Alert routing. Created only when `alert_email_receivers` is supplied. |
| Substrate-deletion alert | `azurerm_monitor_activity_log_alert` | The substrate guards itself (ADR 0008 §3): fires on attempted workspace deletion. |

ADR 0008 §3 calls for substrate-protecting policies to run Deny from day one; that Deny-mode protection (a deny-delete policy or resource lock) is deferred, and the activity-log alert is the interim detective control.

Anchored on AVM per [ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md). The consumer (an environment root) owns the resource group and supplies names from `foundation/naming`; this module does not create the RG (ADR 0004 / ADR 0024).

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `log_analytics_workspace_name` | string | yes | Workspace name (from `foundation/naming`). |
| `application_insights_name` | string | yes | App Insights component name (from `foundation/naming`). |
| `resource_group_name` | string | yes | Existing RG the substrate is created in. |
| `location` | string | yes | Azure region (lowercase). |
| `tags` | map(string) | no | Tags for every resource (from `foundation/tags`). |
| `log_analytics_retention_in_days` | number | no | Hot-tier retention. Default 30 (ADR 0005); 30–730. |
| `log_analytics_daily_quota_gb` | number | no | Daily ingestion cap (cost guardrail, AP-002). Null = no cap. |
| `log_analytics_sku` | string | no | Pricing SKU. Default `PerGB2018`. |
| `application_insights_retention_in_days` | number | no | App Insights retention. Default 90. |
| `name_prefix` | string | no | Prefix for the alert and action-group names. Default `platform`. |
| `action_group_name` | string | no | Action group name. Created only with receivers. Default `<name_prefix>-alerts`. |
| `action_group_short_name` | string | no | Action group short name (≤12 chars). Default: `name_prefix` truncated to 12. |
| `alert_email_receivers` | list(object) | no | `{name, email_address}` list. Empty (default) → no action group. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `log_analytics_workspace_id` | string | **The substrate input** consumers wire into `foundation/diagnostic-settings` and the workload patterns. |
| `application_insights_id` | string | App Insights component resource ID. |
| `application_insights_connection_string` | string (sensitive) | The collector's Azure Monitor exporter target. |
| `application_insights_instrumentation_key` | string (sensitive) | Legacy; prefer the connection string. |
| `action_group_id` | string | Platform action group ID; null when no receivers. |

## Composition

This module is consumed at the environment-root boundary (ADR 0004) — it is the *producer* of the substrate that `foundation/diagnostic-settings` then enforces routing to:

```hcl
module "substrate" {
  source                       = "../../platform-services/observability-substrate"
  log_analytics_workspace_name = module.naming.names.log_analytics_workspace
  application_insights_name    = module.naming.names.application_insights
  resource_group_name          = azurerm_resource_group.platform.name
  location                     = var.location
  tags                         = module.tags.tags
}

module "diagnostic_settings" {
  source                     = "../../foundation/diagnostic-settings"
  policy_management_group_id = var.platform_management_group_id
  log_analytics_workspace_id = module.substrate.log_analytics_workspace_id # ← the seam
}
```

## Private operation requires an AMPLS (hard prerequisite)

With `internet_ingestion_enabled` / `internet_query_enabled` at their `false` defaults, the workspace and App Insights component accept traffic only over private networking. That path does not exist until an **Azure Monitor Private Link Scope (AMPLS)** wired to private DNS and a private endpoint reaches it — [`networking/hub`](../../networking/hub/) provisions exactly that: pass this module's `log_analytics_workspace_id` and `application_insights_id` into the hub's `ampls_linked_resource_ids`. Without that wiring:

- agents and the collector cannot ingest telemetry, and
- operators cannot query the workspace from the portal,

unless the request originates from an AMPLS-connected network. For an evaluation environment without private networking, set both flags to `true` knowingly — that is the documented escape hatch, not the default.

## What's deferred (v0.1.0)

- **The OTel collector deployment** — host-dependent (AKS / Container Apps); a separate concern from the substrate it writes to.
- **Warm/cold retention tiers** — ADR 0005's 1-year warm and 7-year cold (Blob + Parquet) tiers. v0.1.0 ships the hot tier (LAW retention); tiering is an additive follow-up.
- **Cardinality budgets and semantic-convention enforcement at ingest** — these live on the collector (ADR 0005 §2), not the substrate store.
- **Owner-based alert fan-out** — the action group takes email receivers; routing per `owner` tag (ADR 0010) is the consumer's to expand.

## Cites

- Implements [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md) — the substrate every signal flows into.
- Anchored on [ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md) (AVM) and composed per [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md) (outputs, not imports).
- Private-by-default per [ADR 0018](../../../docs/decisions/0018-network-topology-hub-spoke.md); self-guarding per [ADR 0008 §3](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md).
- Prevents [AP-001 (bolted-on monitoring)](../../../docs/anti-patterns.md#ap-001--bolted-on-monitoring), [AP-002 (telemetry dumping ground)](../../../docs/anti-patterns.md#ap-002--telemetry-dumping-ground), and supports the signal-parity answer to [AP-011](../../../docs/anti-patterns.md#ap-011--lower-env-signal-gap).
