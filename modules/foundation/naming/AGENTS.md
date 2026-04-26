# foundation/naming — AI agent notes

Module-specific guidance for AI agents working in `modules/foundation/naming/`. Read alongside [`README.md`](./README.md).

## What this module is

A pure-logic module: takes inputs, computes names, outputs a map. No Azure resources, no policy, no monitoring. The simplest module shape in the repo, included as the **exemplar** for module conventions.

If a future request says *"add monitoring to this module"* or *"make this module create the resource group it names"* — push back. That would conflate naming (the contract this module owns) with resource creation (which belongs in the modules that consume names).

## Common compositions

Consumers (examples, environment roots, workload patterns) typically:

1. Instantiate this module first in their root.
2. Pass `module.naming.names.<resource_type>` to downstream resources/modules.
3. Treat outputs as the contract — never bypass to construct names manually.

If a downstream module wants a name for a resource type *not* in `local.names`, the right responses (in order of preference):

1. Open a PR adding the type to this module.
2. Construct from `module.naming.parts.hyphen` or `parts.compact` (acceptable but flag for future PR).

The wrong response: hand-roll a name that "matches the convention" inline. That fragments the convention.

## Anti-patterns specific to this module

- **DO NOT** add bypass inputs (`override_name`, `name_prefix`) to allow consumers to skip the convention. The whole point is one source of truth. If a deviation is genuinely needed, that's a deviation ADR per [docs/golden-paths.md](../../../docs/golden-paths.md), not a module flag.
- **DO NOT** add resource types speculatively. The list grows on-demand as workload patterns require them.
- **DO NOT** add provider blocks or resources. This module is pure-logic; the moment it provisions, its plan/apply behavior changes and the contract breaks.
- **DO NOT** silently change name construction for an existing resource type without an ADR. Renaming a resource type's output is a breaking change for every consumer.

## Why this module has no `policy/` or `monitoring/`

It produces no Azure resources. There is nothing to govern with policy and nothing to alert on. Empty `ships` arrays in `manifest.yaml` reflect this; the module's `README.md` notes it explicitly. Per [AGENTS.md Hard Rule 1](../../../AGENTS.md), "ships its own observability and policy" applies to modules that produce auditable resources. This one does not.

## Adding a resource type — checklist

1. Identify Azure naming constraints for the resource (length, allowed characters, global uniqueness, casing).
2. Add the construction in `main.tf` `locals`. Use:
   - `parts_hyphen` for resources that allow hyphens.
   - `parts_compact` for resources that don't.
   - Custom construction if the resource has unusual constraints.
3. Add the entry to `local.names`.
4. Add a row to the README's resource-types table.
5. Add an assertion to `tests/convention_compliance.tftest.hcl`.
6. Open a PR per [CONTRIBUTING.md](../../../CONTRIBUTING.md).

The manifest does not need updating for new resource types — `outputs.names` is typed as a generic object, so adding keys is non-breaking at the contract level.

## Validation expectations

CI runs (or will run, once the workflow is in place):

- `terraform fmt`
- `terraform validate`
- `terraform test` (executes both `tests/convention_compliance.tftest.hcl` and `tests/input_validation.tftest.hcl`)
- Manifest schema validation against `schemas/module-manifest.schema.json`
- Manifest-vs-code coherence (inputs in manifest match `variables.tf`; outputs in manifest match `outputs.tf`)
