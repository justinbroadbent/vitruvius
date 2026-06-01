# workload-patterns/web-api-aks — AI agent notes

Module-specific guidance for AI agents working in `modules/workload-patterns/web-api-aks/`. Read alongside [`README.md`](./README.md).

## What this module is

The first workload pattern in the repo. Establishes the shape every workload pattern should follow:

- **Cross-cutting in, intra-app free.** Required inputs are only what the platform standardizes (names, tags, observability targets, identity federation). The app team's deployment YAML is none of this module's business.
- **Composition by output data only.** Names come from `foundation/naming` outputs; tags come from `foundation/tags` outputs. The workload pattern never imports the foundation modules. Per [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md).
- **Ships its own policy and monitoring.** The KV hardening initiative is part of this module, not bolted on later. Per [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md).

If a future workload pattern (`function-event-driven`, `data-pipeline`, `apim-bff`) gets added, follow the same shape. Inconsistency between workload patterns is its own anti-pattern.

## Anti-patterns specific to this module

- **DO NOT** add a `kubernetes` provider or any `kubernetes_*` resources. The deliberate provider surface is azurerm-only. Adding kubernetes resources forces consumers to wire cluster credentials and turns a workload-pattern into a deployment tool. If a real consumer demands it, propose an ADR for a v0.2 split (azurerm-only inner module + kubernetes outer module).
- **DO NOT** add a `client_secret` output, a `kubelet_identity` output, or any path that creates static credentials. Workload-identity federation is the contract; static secrets are an anti-pattern per [ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md).
- **DO NOT** flip the default of `policy_enforcement_mode` to `Default` or change the policy effects' defaults from `Audit`. Audit-before-Deny per [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) is the contract; promotion is human review with evidence.
- **DO NOT** add an `extra_role_assignments` map that grants the workload identity arbitrary roles. The principle is "explicit Azure RBAC at the consumer boundary" — consumers grant additional roles using `output.workload_identity_principal_id` themselves.
- **DO NOT** reintroduce a separate "where definitions live" input (an earlier draft had `policy_definition_subscription_id`). It was vestigial: `azurerm_policy_definition` / `azurerm_policy_set_definition` take no subscription argument — definitions are created in whichever subscription the `azurerm` provider authenticates to. The only real scope choice is `policy_assignment_scope` (where the initiative is *assigned*), which accepts a subscription or a resource-group ID. For genuine cross-subscription definition placement, use a provider `alias` at the consumer boundary — not a string input that silently does nothing.
- **DO NOT** call `foundation/naming` or `foundation/tags` from inside this module. Per ADR 0004 and the manifest schema's `dependencies.repo: maxItems: 0`, in-repo module imports are forbidden.

## Why the federated credential has no `resource_group_name`

In azurerm v4+, `resource_group_name` on `azurerm_federated_identity_credential` is deprecated — `parent_id` (pointing at the UAI) is sufficient because the credential's lifecycle is owned by the UAI. We don't set it. Earlier drafts of this module set it and triggered deprecation warnings; if you see a request to add it back, decline.

## Test approach

Tests use `mock_provider "azurerm"` with explicit `mock_resource` overrides for resources whose IDs are referenced in client-side validation (UAI, KV, policy_definition, policy_set_definition, subscription_policy_assignment). Without the overrides, the synthetic strings the test framework returns by default fail Azure resource ID parsers.

Mock data sources (`azurerm_client_config`) are also overridden so `data.azurerm_client_config.current.tenant_id` returns a stable test value the assertions can check against.

If a future test adds a new resource type, add a matching `mock_resource` block with a properly-formatted Azure resource ID.

## AVM module pinning

The AVM Key Vault module is pinned at `~> 0.10` in `main.tf`. AVM modules iterate quickly and occasionally introduce breaking input changes. When upgrading:

1. Pin to the specific patch version you tested against, not a `~>` constraint.
2. Re-run `terraform test` and watch for new validation failures or input renames.
3. Update this module's `manifest.yaml` `dependencies.avm` version to match.
4. Note the upgrade in a CHANGELOG entry once we have one.

The current AVM KV module emits one deprecation warning under azurerm provider v4 (`enable_rbac_authorization` → `rbac_authorization_enabled`). That's an upstream issue; not this module's concern. It will resolve when AVM updates.

## Why the KV diagnostic policy is `AuditIfNotExists`, not `DeployIfNotExists`

A `DeployIfNotExists` policy that auto-creates a diagnostic setting *would* heal the violation, but it would also create a second source of diagnostic settings (the policy, in addition to this module). When the policy's setting drifts from the module's setting, debugging becomes hard.

`AuditIfNotExists` flags the missing setting. The fix is "the workload pattern wasn't used to create this KV" — which is the real defect. Healing-by-policy obscures that.

## When to add a new workload pattern (vs extending this one)

Extend `web-api-aks` when:
- The variant is a configuration of the same shape (different SKU, additional optional input).
- The cross-cutting story is identical (same identity model, same observability target, same policy initiative).

Create a new workload-pattern module when:
- The cross-cutting story differs (event-driven workloads use Service Bus + Functions; the policy initiative would be different).
- The runtime differs in a way that changes the contract (App Service vs AKS; the federated credential subject is AKS-specific).
- The integration shape differs (APIM facade exposes the API; that's a different pattern, not a flag on this one).

Workload patterns multiply slowly. Three or four total is plausible; ten is not.

## Validation expectations

CI runs (or will run, once the workflow is in place):

- `terraform fmt`
- `terraform validate`
- `terraform test` — both `contract_compliance.tftest.hcl` and `input_validation.tftest.hcl` (15 assertions; uses mock_provider with explicit resource ID overrides)
- Manifest schema validation against `schemas/module-manifest.schema.json`
- Manifest-vs-code coherence (inputs, outputs, ships-policy entries match what's in code and on disk)
- AVM dependency verification (manifest's `dependencies.avm` matches `main.tf`'s `module "key_vault"` source/version)
