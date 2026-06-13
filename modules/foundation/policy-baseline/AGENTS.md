# foundation/policy-baseline — AI agent notes

Module-specific guidance for AI agents working in `modules/foundation/policy-baseline/`. Read alongside [`README.md`](./README.md).

## What this module is

The estate guardrail — the running implementation of [ADR 0025](../../../docs/decisions/0025-deployment-conformance-and-platform-baseline.md) §1's platform baseline. It ships the mandatory Deny/Audit policies that apply to every subscription beneath a management group, so a workload cannot omit them by forking-and-trimming a golden path.

The shape is intentionally parallel to [`foundation/diagnostic-settings`](../diagnostic-settings/): a JSON file per policy, a single initiative, an optional MG-scope assignment, Audit-before-Deny defaults. The difference: these are **Deny/Audit** policies, not `DeployIfNotExists`, so there is **no managed identity, no location, and no remediation role assignment**.

## Anti-patterns specific to this module

- **DO NOT** add a managed identity, `location`, or `azurerm_role_assignment` to the assignment. Deny/Audit policies remediate nothing; an identity here is cargo-culted from the DeployIfNotExists pattern and is wrong.
- **DO NOT** flip the `policy_effect` default from `Audit` to `Deny`. Audit-before-Deny is the contract ([ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md)); promotion is a human-reviewed PR citing audit telemetry.
- **DO NOT** add subscription-scope assignment as a default path. The whole point is MG-scope inheritance; subscription-scope fragments the compliance view and drifts as subscriptions are added.
- **DO NOT** add a per-guardrail effect override. One initiative-wide `policy_effect` keeps the audit-mode evidence coherent. Per-resource tuning that a real adopter needs is an ADR conversation, not a flag.
- **DO NOT** let `allowed_locations` default to an empty list or accept one when deploying. An empty allow-list makes the allowed-locations guardrail deny every region. The `terraform_data.input_invariants` precondition enforces this.

## Adding a new guardrail

1. Author the policy JSON in `policy/<name>.json`: top-level `displayName`, `description`, `mode`, `policyRule` (with `then.effect = [parameters('effect')]`), and `parameters` (must include `effect`). Add any extra parameter (like `listOfAllowedLocations`) only if the rule needs it.
2. Add the entry to `local.policy_files` in `main.tf`.
3. If the guardrail needs an extra initiative parameter, extend the initiative `parameters` and the per-key branch in `local.initiative_references` (see how `allowed-locations` receives `listOfAllowedLocations`).
4. Add the entry to `ships.policy` in `manifest.yaml`.
5. Bump the count assertions in `tests/policy_compliance.tftest.hcl` and the table in `README.md`.

## Why custom definitions, not built-in references

Built-in policy IDs are stable but opaque — the rule, the effect, and the compliance intent live in three places. Authoring custom definitions keeps them in one reviewable file, matching the repo's policy-as-code convention. If an adopter standardizes on Microsoft's built-ins, the initiative can reference them instead without changing the module's input/output contract.

## Test approach

Tests use `mock_provider "azurerm"` with `mock_resource` overrides for the three policy resource types. `policy_compliance.tftest.hcl` covers the no-op / definitions-only / assigned modes, the four-guardrail bundle, the non-enforcing default (Audit-before-Deny), and the empty-`allowed_locations` invariant via `expect_failures = [terraform_data.input_invariants]`. `input_validation.tftest.hcl` covers the variable validations.
