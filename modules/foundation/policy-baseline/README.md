# foundation/policy-baseline

The estate guardrail. Ships the Azure Policy initiative of **mandatory controls every subscription inherits** — assigned once at a management group, so they apply to every workload beneath it whether or not it came through a golden path.

This module is the running implementation of [ADR 0025 §1](../../../docs/decisions/0025-deployment-conformance-and-platform-baseline.md): *if omission would make the estate non-compliant, the control is platform-owned, not a workload brick.* A golden-path module makes the right thing the easy thing; this module makes the wrong thing impossible. You need both — and this is the "impossible" half.

## What it enforces (v0.1.0)

| Guardrail | What it blocks | Maps to |
|---|---|---|
| `app-service-no-public-access` | An App Service with public network access enabled | GLBA Safeguards — access control |
| `app-service-https-only` | An App Service not redirecting HTTP → HTTPS | GLBA Safeguards — transmission security |
| `storage-no-public-blob` | A storage account allowing anonymous public blob access | GLBA Safeguards — access control |
| `allowed-locations` | A resource created outside the approved region list | Data-residency control |

These are **Deny/Audit** policies — unlike the `DeployIfNotExists` safety net in [`foundation/diagnostic-settings`](../diagnostic-settings/), they block rather than remediate, so the assignment needs no managed identity or remediation role grants.

## Two-mode design

Like the other policy-shipping foundation modules, this deploys only when opted in:

- **Default** (no `policy_management_group_id`): no resources created. `guardrail_policies` is still available for documentation.
- **Active** (`policy_management_group_id` supplied): definitions and initiative created at that MG; assignment created when `policy_assignment_scope` is also supplied.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `name_prefix` | string | no | Prefix for the policy resource names. Default `platform`. |
| `policy_management_group_id` | string | no | When supplied, definitions + initiative are created at this MG. When null, the module is a no-op. |
| `policy_assignment_scope` | string | no | MG ID where the initiative is assigned. When null, the initiative is created but not assigned. |
| `policy_enforcement_mode` | string | no | `DoNotEnforce` (default; Audit-before-Deny per ADR 0008) or `Default`. |
| `policy_effect` | string | no | `Audit` (default per ADR 0008), `Deny`, or `Disabled`. Initiative-wide. |
| `allowed_locations` | `list(string)` | no | Approved regions for the allowed-locations guardrail. Default `["eastus", "eastus2"]`; must be non-empty when deploying. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `guardrail_policies` | `list(string)` | Sorted list of guardrail keys in the initiative. Always populated. |
| `initiative_id` | string | Initiative resource ID; null when policy is not deployed. |
| `policy_definition_ids` | `map(string)` | Map of guardrail key to definition ID; empty when policy is not deployed. |
| `assignment_id` | string | Assignment ID; null when `policy_assignment_scope` is not supplied. |

## The Audit-before-Deny lifecycle, applied here

Per [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md):

1. **Day 0 — observe.** Defaults are `policy_effect = "Audit"` and `policy_enforcement_mode = "DoNotEnforce"`. The initiative evaluates and reports violations estate-wide but blocks nothing — you see who *would* be denied before anyone is.
2. **Days 1–60 — measure.** Pull policy-evaluation telemetry from the substrate. Confirm no legitimate workload trips a guardrail (or grant an [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) exemption for the ones that should).
3. **Promote.** A PR flips `policy_effect` to `Deny` and `policy_enforcement_mode` to `Default`, citing the audit evidence. From then on, a non-compliant App Service is refused at creation — by anyone, through any path.

This module does not auto-promote. The audit-and-evidence step is human review.

## Why a management-group scope

The initiative is assigned at a management group so one assignment covers every subscription beneath it — including subscriptions added later. That is the whole point: a workload team cannot create a public App Service in a new subscription because the guardrail was inherited, not opted into. Subscription-scope assignment is an anti-pattern here — it fragments the compliance view and silently drifts as subscriptions are added ([AP-004](../../../docs/anti-patterns.md#ap-004--configuration-drift)).

## Custom definitions, not built-in references

The guardrails ship as custom policy definitions (JSON in `policy/`) rather than references to Azure built-ins. This keeps the module self-contained and reviewable in one place — the rule, its effect parameter, and its compliance intent live together. An adopter who prefers Microsoft's built-ins can swap the definition bodies without changing the module's contract.

## What the tests prove — and what they don't

The `terraform test` suite runs against a mocked provider with no Azure account, so it proves **configuration invariants**: the definitions and initiative are assembled, the four guardrails are bundled, the parameters and effect flow through, the default is Audit-before-Deny (`enforce = false`), and the no-op / definitions-only / assigned modes behave. It does **not** prove that Azure Policy will evaluate a real resource as intended, or actually deny a non-compliant deployment — a mocked plan cannot execute policy evaluation.

Proving enforcement is a real-estate step, and it is the [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) lifecycle rather than a testing gap: assign the initiative in **Audit** at the intended scope, create representative compliant and non-compliant resources, inspect the evaluation results, analyse false positives, and only then promote to **Deny**. The mocked tests guard the module's wiring; the Audit period guards the rule's behaviour.

## Cites

- Implements [ADR 0025](../../../docs/decisions/0025-deployment-conformance-and-platform-baseline.md) §1 — mandatory estate controls are platform-owned and assigned at a management group.
- Honors [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) — Audit-before-Deny defaults; exemptions are first-class.
- Honors [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md) — the guardrail policy ships as code in the module that owns it.
- Prevents [AP-004 (configuration drift)](../../../docs/anti-patterns.md#ap-004--configuration-drift) and [AP-005 (sweeping policy bans)](../../../docs/anti-patterns.md#ap-005--sweeping-policy-bans) — the bans are scoped, evidence-based, and observed before they enforce.
