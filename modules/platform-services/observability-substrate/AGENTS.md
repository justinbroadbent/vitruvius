# platform-services/observability-substrate — AI agent notes

Module-specific guidance for AI agents working in `modules/platform-services/observability-substrate/`. Read alongside [`README.md`](./README.md).

## What this module is

The first `platform-services` module and the implementation of [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md): it produces the Log Analytics workspace + workspace-based Application Insights that the rest of the estate already treats as an input (`log_analytics_workspace_id` in `foundation/diagnostic-settings` and `web-api-aks`). It is the **producer** of the substrate; `foundation/diagnostic-settings` is the policy that **enforces routing into** it. Keep that split.

## Scope boundary — what does NOT belong here

- **DO NOT** add the OTel collector deployment to this module. The collector runs on the platform's compute (AKS / Container Apps) and is host-dependent; this module is only the substrate the collector exports to. A collector module is separate work.
- **DO NOT** create the resource group. The consumer (environment root) owns the RG and passes `resource_group_name` (ADR 0004 / ADR 0024). Same posture as `web-api-aks`.
- **DO NOT** auto-generate names with a `random` suffix or a data source. Names come from `foundation/naming` upstream and are passed in. Determinism matters for the catalog and for drift detection.
- **DO NOT** turn on public network access to "make examples work." Internet ingestion/query default off (ADR 0018, private-by-default). Private-endpoint wiring is the consumer's networking concern.

## Anchored on AVM (ADR 0001)

The workspace and App Insights are AVM modules, not raw `azurerm_*`:

- `Azure/avm-res-operationalinsights-workspace/azurerm` `~> 0.5` — note the input names are prefixed `log_analytics_workspace_*` (e.g. `log_analytics_workspace_retention_in_days`). Its `resource_id` output is the LAW ID.
- `Azure/avm-res-insights-component/azurerm` `~> 0.4` — `workspace_id` wires to the LAW's `resource_id`; outputs `connection_string` and `instrumentation_key` are sensitive.

The action group and the activity-log alert are raw `azurerm_*` — acceptable per ADR 0001 (thin single resources, no AVM wrapper worth taking). When bumping AVM versions, re-check input/output names against the registry and re-run the tests.

`enable_telemetry = false` is set on both AVM modules deliberately: it keeps `terraform test` hermetic (no `modtm` provider resource to mock) and avoids sending AVM usage telemetry to Microsoft from platform infra. Do not flip it on.

## Test approach

Tests use `mock_provider "azurerm"` with `mock_resource` overrides for the resources the AVM modules create internally — `azurerm_log_analytics_workspace`, `azurerm_application_insights`, plus the action group and activity-log alert — using real-shaped resource IDs so the AVM `resource_id` outputs resolve. `azurerm_subscription` is mocked as data. This is the same pattern `web-api-aks` uses for its AVM Key Vault.

- `contract_compliance.tftest.hcl` — the substrate exposes the workspace/App Insights IDs and connection string; the action group is created and wired into the deletion alert **only** when receivers are supplied; the deletion alert always ships.
- `input_validation.tftest.hcl` — rejects sub-floor LAW retention, unsupported App Insights retention values, an over-long action-group short name, uppercase location, and a zero daily quota.

If you add a resource that reads another resource's computed attribute, add a `mock_resource` default for it or the test plan will carry an unknown and assertions may not evaluate.

## Things that will bite you

- **Action-group short name is capped at 12 characters** by Azure. The validation enforces it; don't relax it.
- **App Insights retention is an enum**, not a free range (30/60/90/120/180/270/365/550/730). The validation lists the allowed set; keep it in sync with Azure if it changes.
- **The activity-log alert needs `location = "global"`** in azurerm 4.x and a subscription-level scope; it filters to the workspace via `criteria.resource_id`.

## When extending toward full ADR 0005

The deferred pieces (warm/cold retention tiers, cardinality budgets, semantic-convention enforcement) are **additive**. Retention tiering (LAW archive + a cold Blob/Parquet store) belongs here; cardinality budgets and ingest-time conventions belong on the **collector**, not the store — do not bolt collector concerns onto this module.
