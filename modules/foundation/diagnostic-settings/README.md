# foundation/diagnostic-settings

Substrate-routing safety net. Ships the Azure Policy initiative that ensures common Azure resources route diagnostic settings to the platform Log Analytics workspace.

This module is the policy-side enforcement of [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md): **all platform observability flows through the substrate**. It exists because workload-pattern modules already wire diagnostic settings on the resources they own — but ad-hoc resources, legacy migrations, and resources created outside the IaC discipline need a fallback. Without this module, [AP-001 (bolted-on monitoring)](../../../docs/anti-patterns.md#ap-001--bolted-on-monitoring) re-emerges as drift.

## Two-mode design

Like [`foundation/tags`](../tags/), this module deploys policy only when explicitly opted in:

- **Default** (no `policy_management_group_id`): no resources created. Useful in environments not yet ready to enforce substrate routing.
- **Active** (`policy_management_group_id` supplied): definitions and initiative created at that MG; assignment created when `policy_assignment_scope` is also supplied.

The `covered_resource_types` output is always available regardless of mode — useful for documentation and dashboards.

## Resource types covered (v0.1.0)

| Type | Logs routed |
|---|---|
| `Microsoft.KeyVault/vaults` | `allLogs` (AuditEvent + AzurePolicyEvaluationDetails) + AllMetrics |
| `Microsoft.ContainerService/managedClusters` | All control-plane categories (kube-apiserver, kube-audit, kube-audit-admin, kube-controller-manager, kube-scheduler, cluster-autoscaler, guard) + AllMetrics |
| `Microsoft.ServiceBus/namespaces` | `allLogs` + AllMetrics |
| `Microsoft.Web/sites` | `allLogs` + AllMetrics |
| `Microsoft.ApiManagement/service` | `allLogs` (GatewayLogs, WebSocketConnectionLogs) + AllMetrics |

Notably **deferred** to v0.2 because of nested-resource complexity:

- `Microsoft.Storage/storageAccounts` — needs four sub-service settings (blob, queue, table, file).
- `Microsoft.Web/sites/slots` — deployment slots are children of sites.
- `Microsoft.Sql/servers/databases` — per-database, not per-server.
- `Microsoft.DocumentDB/databaseAccounts` — Cosmos DB has special diag categories per API.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `policy_management_group_id` | string | no | When supplied, definitions + initiative are created at this MG. When null, the module is a no-op. |
| `log_analytics_workspace_id` | string | conditional | Required when `policy_management_group_id` is supplied. Resource ID of the substrate LAW. |
| `policy_assignment_scope` | string | no | MG ID where the initiative is assigned. When null, the initiative is created but not assigned. |
| `policy_enforcement_mode` | string | no | `DoNotEnforce` (default; Audit-before-Deny per ADR 0008) or `Default`. |
| `policy_effect` | string | no | `AuditIfNotExists` (default per ADR 0008), `DeployIfNotExists`, or `Disabled`. Initiative-wide. |
| `policy_assignment_location` | string | no | Region for the assignment's managed identity. Required by Azure for `DeployIfNotExists` policies. Defaults to `eastus`. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `covered_resource_types` | `list(string)` | Sorted list of Azure resource types the initiative covers. Always populated. |
| `initiative_id` | string | Initiative resource ID; null when policy is not deployed. |
| `policy_definition_ids` | `map(string)` | Map of policy key to definition ID; empty when policy is not deployed. |
| `assignment_id` | string | Assignment ID; null when `policy_assignment_scope` is not supplied. |

## The Audit-before-Deny lifecycle, applied here

Per [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md):

1. **Day 0 — observe.** Default deployment uses `policy_effect = "AuditIfNotExists"` and `policy_enforcement_mode = "DoNotEnforce"`. Combined, the assignment evaluates and reports drift but does nothing else.
2. **Days 1–60 — measure.** Pull policy-evaluation telemetry from the substrate. Identify resources that would be modified by `DeployIfNotExists`. Confirm the LAW can absorb the additional log volume.
3. **Promote.** PR to flip both `policy_effect` to `DeployIfNotExists` and `policy_enforcement_mode` to `Default`. Cite the audit telemetry in the PR description.

This module does not auto-promote. The audit-and-evidence step is human review.

When the initiative is assigned, the module also grants the assignment's managed identity **Log Analytics Contributor** and **Monitoring Contributor** at the assignment scope — Azure grants the policies' `roleDefinitionIds` automatically only for portal-created assignments, so without these the `DeployIfNotExists` remediation would fail authorization after promotion.

## Why DeployIfNotExists here, not in workload patterns

A reasonable question: if the workload pattern (`web-api-aks`) for Key Vault uses `AuditIfNotExists` for its KV diagnostic-setting policy, why does this module's KV policy support `DeployIfNotExists`?

Because they answer different questions:

| Module | Question | Answer |
|---|---|---|
| `web-api-aks` | "Did our pattern create the diag setting we expected?" | `AuditIfNotExists` — drift means the pattern wasn't used; healing would obscure that. |
| `foundation/diagnostic-settings` | "Does any KV in the estate emit logs to the substrate?" | `DeployIfNotExists` (after promotion) — for resources outside the pattern, healing IS the safety net. |

The two can coexist on the same KV: the workload pattern's setting satisfies both policies' `existenceCondition` (which checks for any setting with a `workspaceId`). The foundation policy doesn't double-deploy.

## Existence condition design

Every member policy uses the same `existenceCondition`:

```json
{
  "field": "Microsoft.Insights/diagnosticSettings/workspaceId",
  "exists": "true"
}
```

This matches **any** diagnostic setting routing to a workspace, not specifically *the substrate workspace*. Trade-off:

- **Pro:** Resources whose owning workload pattern already created a setting are satisfied — no double-deployment.
- **Con:** A resource routing to a *non-substrate* workspace would be considered satisfied. That's a separate compliance concern (substrate routing fidelity), not handled by this initiative.

If the platform later needs to enforce *which* workspace, that's a new policy (probably `audit` effect, separate initiative) — not a tweak to this one.

## Assignment scope choice

The initiative is intended to be assigned at a management-group scope so it covers all subscriptions in the platform org. Subscription-scope assignment is technically possible but anti-pattern: it produces N copies of the same evaluation work, fragments the policy-compliance dashboard, and silently drifts when subscriptions are added without human action. If you find yourself wanting subscription-scope assignment, instead reconsider the management-group structure.

## Cites

- Implements [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md) — the substrate is the single observability backplane.
- Honors [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) — Audit-before-Deny defaults.
- Honors [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md) — substrate-routing policy ships with the foundation module that owns the contract.
- Prevents [AP-001 (bolted-on monitoring)](../../../docs/anti-patterns.md#ap-001--bolted-on-monitoring) and [AP-002 (telemetry dumping ground)](../../../docs/anti-patterns.md#ap-002--telemetry-dumping-ground).

## Why this module ships no monitoring

The module's resources are policy objects — the *enforcement* half of the monitoring story. Compliance state for the initiative surfaces through Azure Policy evaluation telemetry in the substrate ([ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md)). The empty `ships.monitoring` array in `manifest.yaml` reflects this; per [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md), missing-because-not-applicable is stated, not implied.
