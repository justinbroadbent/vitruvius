# foundation/diagnostic-settings — AI agent notes

Module-specific guidance for AI agents working in `modules/foundation/diagnostic-settings/`. Read alongside [`README.md`](./README.md).

## What this module is

The substrate-routing safety net. Ships the policy initiative that ensures every common Azure resource emits diagnostic logs to the platform Log Analytics workspace. Where workload-pattern modules wire diagnostic settings on the resources they own (cleanly), this module is the enforcement layer for everything that escapes the workload-pattern discipline.

This is the second policy-shipping foundation module after [`foundation/tags`](../tags/). The shape is intentionally parallel: a JSON file per policy, a single initiative, an optional assignment, audit-before-deny defaults.

## Anti-patterns specific to this module

- **DO NOT** add a per-resource-type effect override (e.g., `keyvault_effect`, `aks_effect`). The single `policy_effect` input keeps the initiative coherent — flipping individual policies fragments the audit-mode evidence into per-type stories that are harder to reason about. If a real consumer needs per-type tuning, that's an ADR conversation, not a flag.
- **DO NOT** widen the `existenceCondition` to require routing specifically to the substrate workspace. That's a separate compliance concern (substrate-fidelity); a separate audit-effect policy in a future initiative is the right shape. Conflating the two breaks the safety-net promise.
- **DO NOT** auto-create the LAW or treat `log_analytics_workspace_id` as optional with a data-source default. The LAW lives in `platform-services/observability` (or a similar substrate-owning module). This module is a consumer of the substrate, not its owner.
- **DO NOT** flip the `policy_effect` default from `AuditIfNotExists` to `DeployIfNotExists`. Audit-before-Deny is the contract; promotion is human review with telemetry per ADR 0008.
- **DO NOT** add subscription-scope assignment as a default path. The initiative is designed for MG-scope assignment. Subscription-scope means N evaluation copies and silent drift when subscriptions are added.

## Adding a new resource type

The current set of five (KV, AKS, Service Bus, App Service, APIM) is the v0.1.0 scope. Adding a new type is a four-step PR:

1. Author the policy JSON in `policy/<type>-route-to-substrate.json`. The structure must match the existing files: top-level `displayName`, `description`, `mode`, `policyRule` (with the resource-type `if.equals` and the DeployIfNotExists `then.details.deployment.template`), and `parameters` (must include `effect` and `logAnalyticsWorkspaceId`).
2. Add the entry to `local.policy_files` in `main.tf`.
3. Add the entry to the `ships.policy` list in `manifest.yaml`.
4. Add the resource type to the `covered_resource_types_enumerates_all_five` test (and rename the test) in `tests/policy_compliance.tftest.hcl`.
5. Update the resource-types table in `README.md`.

The manifest does not need updating for new resource types beyond the `ships.policy` list — `covered_resource_types` is typed as a generic list, so adding entries is non-breaking at the contract level.

### Resource types with nested-resource complexity

Some resource types have child resources whose diagnostic settings are configured separately:

- `Microsoft.Storage/storageAccounts` — each subservice (blob, queue, table, file) needs its own setting.
- `Microsoft.Web/sites/slots` — deployment slots are children.
- `Microsoft.Sql/servers/databases` — per-database, not per-server.
- `Microsoft.DocumentDB/databaseAccounts` — Cosmos has API-specific categories.

For these, write **one policy per child resource type**, not a single parent policy that tries to cover children. The ARM template's `type` field must match the actual resource type the diagnostic setting attaches to.

## Why the policies use a single `existenceCondition` shape

The `existenceCondition` is `Microsoft.Insights/diagnosticSettings/workspaceId exists true` for every member policy. This is intentional:

- It prevents double-deployment when a workload pattern already created a setting on the resource.
- It keeps the policy semantics uniform across resource types.
- It does NOT enforce *which* workspace — that's a separate concern.

If a request asks to make the existence condition require the substrate-LAW workspace ID specifically, decline and propose a separate "substrate-routing-fidelity" policy in a different initiative. Mixing the two concerns breaks the safety-net contract.

## Why the cross-variable validation uses `terraform_data` precondition

Variable-level `validation` blocks in Terraform 1.7 cannot reference other variables. The cross-variable invariant ("LAW required when MG ID supplied") is enforced via a `terraform_data` resource with a `precondition` block — the standard pattern for 1.7-1.8 modules. In Terraform 1.9+, variable validations CAN reference other variables, but this module pins to 1.7 to keep portability with the rest of the foundation layer.

If this module is ever bumped to 1.9+ (e.g., to consume an AVM dependency that requires it), the `terraform_data` resource can be removed and the invariant moved into a `validation` block on `log_analytics_workspace_id`. The expect_failures target in `tests/policy_compliance.tftest.hcl` will need to change accordingly.

## Test approach

Tests use `mock_provider "azurerm"` with explicit `mock_resource` overrides for the policy resources whose IDs are referenced in client-side validation. Same pattern as `foundation/tags`. The `terraform_data` precondition test uses `expect_failures = [terraform_data.input_invariants]` — a slightly unusual target because the failure surfaces at the resource level, not the variable level.

## Validation expectations

CI runs (or will run, once the workflow is in place):

- `terraform fmt`
- `terraform validate`
- `terraform test` — both `policy_compliance.tftest.hcl` and `input_validation.tftest.hcl` (11 assertions; uses `mock_provider`)
- Manifest schema validation against `schemas/module-manifest.schema.json`
- Manifest-vs-code coherence (inputs, outputs, `ships.policy` entries match what's in code and on disk)
- JSON validity of every file in `policy/` (separate from manifest schema validation; ARM templates inside `then.details.deployment` are not validated structurally)
