# foundation/tags

Authority on the tag taxonomy. Produces a tag map suitable for any Azure resource's `tags` argument **and** ships the Azure Policy initiative that enforces the taxonomy.

This module is the canonical implementation of [ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md). It exists to prevent [AP-008 — Tag chaos](../../../docs/anti-patterns.md#ap-008--tag-chaos): every estate that lets teams pick their own tags ends up with `Owner=Jane`, `owner=jane.doe`, `Env=Prod`, `environment=PROD`, and a manual finance-vs-operations reconciliation every quarter.

## Two modes

This module has a deliberate split:

1. **Tag-map mode** (default) — produces just the tag map. Suitable for any module or root config that wants the canonical tag map; the policy initiative is assumed to be assigned once at a higher scope.
2. **Tag-map-plus-policy mode** — when `policy_management_group_id` is supplied, the module also creates the policy definitions, bundles them into the `vitruvius-tag-taxonomy` initiative, and assigns it at that management group.

The tag map is always produced; policy is opt-in. This keeps consumers free to invoke this module per-workload for the tag map without duplicating policy assignments.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `owner` | string | yes | Team alias (Backstage group, not a person). 2–40 chars, lowercase alphanumeric or hyphens. |
| `env` | string | yes | One of `prod`, `staging`, `dev`, `sandbox`. |
| `cost_center` | string | yes | Format `cc-NNNN` (e.g., `cc-1001`). |
| `data_classification` | string | yes | One of `public`, `internal`, `confidential`, `restricted`. |
| `business_criticality` | string | yes | One of `tier-0`, `tier-1`, `tier-2`, `tier-3`. |
| `app` | string | no | Optional application alias matching a Backstage component. |
| `component` | string | no | Optional sub-component within an app. |
| `lifecycle_stage` | string | no | One of `stable`, `experimental`, `deprecated`. Emitted as the `lifecycle` tag key. |
| `policy_management_group_id` | string | no | When supplied, the policy initiative and assignment are created at this MG. When null, the module produces only the tag map. |
| `policy_enforcement_mode` | string | no | `DoNotEnforce` (default; Audit-mode per ADR 0008) or `Default` after promotion. |
| `policy_assignment_location` | string | no | Region for the assignment's managed identity. Defaults to `eastus`. Required by Azure because the inherit-tag policy uses the `modify` effect. |

The Terraform variable name `lifecycle_stage` exists because `lifecycle` shadows the Terraform meta-argument keyword. The emitted *tag key* is `lifecycle`, matching ADR 0010.

## Outputs

| Name | Type | Description |
|---|---|---|
| `tags` | `map(string)` | Pass directly to a resource's `tags`. Required tags always present; optional tags present only when supplied. |
| `required_tags` | `map(string)` | Subset containing only the five required tags. |
| `vocabularies` | object | Allowed values per vocabulary-controlled tag. |
| `initiative_id` | string | Initiative resource ID; null when policy is not deployed. |
| `policy_definition_ids` | `map(string)` | Map of policy key to definition ID; empty when policy is not deployed. |
| `assignment_id` | string | Assignment resource ID; null when policy is not deployed. |

## Composition

Per [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md), consumers compose by reading outputs:

```hcl
module "tags" {
  source = "../../modules/foundation/tags"

  owner                = "member-services"
  env                  = "prod"
  cost_center          = "cc-2002"
  data_classification  = "confidential"
  business_criticality = "tier-1"
}

resource "azurerm_resource_group" "this" {
  name     = "rg-memberapi-prod"
  location = "eastus"
  tags     = module.tags.tags
}
```

Workload-pattern modules accept a `tags` input rather than re-instantiating this module — keeping a single tag-source-of-truth per root.

## What this module ships in `policy/`

Nine policy definitions, bundled into one initiative:

| File | Effect | Purpose |
|---|---|---|
| `require-tag-owner.json` | `Audit` (parameterized) | Resource missing `owner` tag is flagged. |
| `require-tag-env.json` | `Audit` (parameterized) | Resource missing `env` tag is flagged. |
| `require-tag-cost-center.json` | `Audit` (parameterized) | Resource missing `cost-center` tag is flagged. |
| `require-tag-data-classification.json` | `Audit` (parameterized) | Resource missing `data-classification` tag is flagged. |
| `require-tag-business-criticality.json` | `Audit` (parameterized) | Resource missing `business-criticality` tag is flagged. |
| `allowed-values-env.json` | `Audit` (parameterized) | Reject `env` values outside the vocabulary. |
| `allowed-values-data-classification.json` | `Audit` (parameterized) | Reject `data-classification` values outside the vocabulary. |
| `allowed-values-business-criticality.json` | `Audit` (parameterized) | Reject `business-criticality` values outside the vocabulary. |
| `inherit-tag-from-resource-group.json` | `modify` | Auto-inherit a tag from the RG when missing on the resource. Instantiated 5 times in the initiative — once per required tag. |

The five `require-tag-*` and three `allowed-values-*` policies expose an `effect` parameter (`Audit` / `Deny` / `Disabled`, default `Audit`). Per [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md), promotion to `Deny` is a separate PR with Audit-mode evidence — not a flag flip in this module.

## Audit-before-Deny lifecycle

The assignment is created with `enforce = false` (`DoNotEnforce` mode) by default. This combines with the policies' default `Audit` effect to produce evaluation-only behavior at first deployment. Promotion path:

1. Run the assignment for 30–90 days.
2. Pull Audit-mode telemetry from the observability substrate ([ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md)) to count would-be denials, identify owners, and confirm no false positives.
3. PR to promote: set `policy_enforcement_mode = "Default"` and (separately, at the assignment scope or via parameters) flip the `effect` parameters from `Audit` to `Deny`.

This module does not auto-promote. The audit-and-evidence step is the point.

## Vocabulary changes

Adding a value to an existing vocabulary (e.g., adding `tier-4`) is two coordinated edits:

1. Update the vocabulary list in the relevant `allowed-values-*.json` policy.
2. Update `local.vocabularies` in `main.tf` to match.

A test asserts the two stay in sync — `vocabularies_match_adr_0010` will fail if drift is introduced. ADR 0010 must also be updated; the manifest's `cites.decisions` list will catch drift in PR review.

Removing a value is a breaking change. Per ADR 0010, it requires a back-fill plan for existing resources before promotion.

## Why tagging is cross-cutting (and why this module owns it)

Per [docs/golden-paths.md](../../../docs/golden-paths.md) § "Defining cross-cutting", tagging is one of the six concerns the platform standardizes globally. This module's `cross_cutting.tagging = true` flag in `manifest.yaml` is the marker that this is the canonical implementation. No other module sets `cross_cutting.tagging = true`.

## Cites

- Implements [ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md): the tag taxonomy this module enforces.
- Follows [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md): Audit-before-Deny lifecycle for the policies it ships.
- Honors [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md): policy ships with the module that owns the contract.
- Prevents [AP-008](../../../docs/anti-patterns.md#ap-008--tag-chaos).
