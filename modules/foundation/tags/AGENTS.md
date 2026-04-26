# foundation/tags — AI agent notes

Module-specific guidance for AI agents working in `modules/foundation/tags/`. Read alongside [`README.md`](./README.md).

## What this module is

The authority on the tag taxonomy. Two outputs in one module:

1. A canonical tag map (`output.tags`) consumers pass into Azure resources.
2. The Azure Policy initiative that enforces the taxonomy across the estate (deployed only when `policy_management_group_id` is supplied).

This is the only module in the repo with `cross_cutting.tagging = true`. If a future change proposes adding a second source of tags or a second tag-policy module, push back hard — it fragments the taxonomy.

## Why this module is one module, not two

A previous design considered splitting into a pure-logic `foundation/tags-map` module and a separate `foundation/tags-policy` module. Rejected because:

- The vocabularies live in two places (the tag-map outputs and the `allowed-values-*` policies). Splitting them invites drift; keeping them in one module lets a single test (`vocabularies_match_adr_0010`) catch it.
- `cross_cutting.tagging` would have to be set on both modules, which contradicts the schema description ("only `foundation/tags` sets this").
- Per [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md), composition is by output data, not by module-to-module imports. A two-module split would tempt a third orchestrator module — exactly the shape ADR 0004 forbids.

If asked to split, refer to this section before agreeing.

## Common compositions

Workload-pattern modules accept `tags` as an input (a `map(string)`). The root config:

1. Instantiates `foundation/tags` once.
2. Passes `module.tags.tags` to every workload-pattern module.

Workload-pattern modules **do not** instantiate `foundation/tags` themselves — that produces N copies of the tag map per environment, defeating the single-source-of-truth.

The tag-policy initiative is typically assigned **once** at a management group, by a foundation-level root config. Workload roots set `policy_management_group_id = null` (the default) so they get only the tag map.

## Anti-patterns specific to this module

- **DO NOT** add a `free_form_tags` input or `extra_tags` map. The whole point is the controlled vocabulary. If a use case demands a new tag, it goes through ADR 0010 amendment.
- **DO NOT** add tag overrides per-resource (e.g., `override_owner` for a one-off resource). Ownership is at team granularity by design.
- **DO NOT** flip the `effect` defaults in the policy JSONs from `Audit` to `Deny`. Promotion is a deliberate PR with audit-mode evidence per ADR 0008, not a default change.
- **DO NOT** auto-promote `policy_enforcement_mode` to `Default` based on time-elapsed or any heuristic. The audit-and-evidence step is human review by design.
- **DO NOT** broaden `inherit-tag-from-resource-group` to inherit from subscription or management group scope. RG-scoped inheritance is the ADR 0010 contract; deeper inheritance creates surprise across tenant boundaries.

## When extending vocabularies

Adding a value to a vocabulary (e.g., a new `business-criticality` tier):

1. Update `local.vocabularies` in `main.tf`.
2. Update the corresponding `allowed-values-<tag>.json` policy file.
3. Update [ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md) to document the addition.
4. Run `terraform test`; the `vocabularies_match_adr_0010` assertion confirms map-and-policy parity.

Adding a new required tag is more invasive: it touches `variables.tf`, `main.tf`, ADR 0010, and any consumer that supplies tag inputs. Per ADR 0010, promote in `Audit` mode for a back-fill window before flipping to `Deny`.

## Why this module has a `policy/` directory full of JSON

Two reasons:

1. **Auditability.** Each policy is a standalone, inspectable JSON file. An auditor can read `require-tag-owner.json` without running Terraform.
2. **Schema portability.** The JSON files are valid Azure Policy definition bodies. They can be deployed by tools other than Terraform if the situation demands it.

The Terraform code reads each file with `file()` + `jsondecode()`. The JSON is the source of truth; Terraform is the deployment vehicle.

## Why the module accepts a `policy_assignment_location`

The `inherit-tag-from-resource-group` policy uses the `modify` effect, which requires the assignment to have a system-assigned managed identity, which requires a `location`. The location does not affect where the policy applies — it just hosts the identity. Default `eastus`; override only if a tenant-policy or region-residency requirement demands.

## Validation expectations

CI runs (or will run, once the workflow is in place):

- `terraform fmt`
- `terraform validate`
- `terraform test` — both `tag_map_compliance.tftest.hcl` and `input_validation.tftest.hcl` (uses `mock_provider "azurerm"` so no Azure credentials needed)
- Manifest schema validation against `schemas/module-manifest.schema.json`
- Manifest-vs-code coherence (inputs, outputs, ships-policy entries match what's in code and on disk)
