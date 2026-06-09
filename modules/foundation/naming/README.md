# foundation/naming

Pure-logic module that produces canonical Azure resource names from a small set of inputs. Outputs a map of resource type to generated name. **No Azure resources are created.**

This module exists to prevent the naming-chaos cousin of [AP-008 (tag chaos)](../../../docs/anti-patterns.md#ap-008--tag-chaos): every estate that lets teams choose their own naming patterns ends up with `MyApp-Prod-EastUS-001` next to `myapp-prod-eus-1` next to `app01-production`. Cost reports, automation, and humans all suffer.

## Naming convention

```
<resource-abbr>-<org>-<workload>-<env>-<region-abbr>-<instance>
```

For resources that disallow hyphens (storage accounts, container registries), the compact form is used:

```
<resource-abbr><org><workload><env><region-abbr><instance>
```

Length-limited types (storage accounts, Key Vaults) fall back to a compact form with a deterministic hash suffix when the inputs exceed the cap. See `main.tf` for the full per-resource construction.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `org` | string | yes | Organization short code; 2–5 lowercase alphanumeric. |
| `workload` | string | yes | Workload alias matching a Backstage component. 2–15 chars: lowercase alphanumeric or hyphens. |
| `env` | string | yes | One of: `prod`, `staging`, `dev`, `sandbox`. Matches tag taxonomy ([ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md)). |
| `region` | string | yes | Azure region (long form, e.g., `eastus`). Mapped to a short code in names. |
| `instance` | string | no | Two-digit suffix. Default `01`. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `names` | object | Resource type → canonical name. |
| `region_abbr` | string | Short region code (e.g., `eus`). |
| `parts` | object | Composed name parts (`hyphen`, `compact`) for resource types not in `names`. |

## Resource types covered

`resource_group`, `virtual_network`, `subnet`, `network_security_group`, `public_ip`, `private_endpoint`, `storage_account`, `key_vault`, `container_registry`, `aks_cluster`, `application_insights`, `log_analytics_workspace`, `function_app`, `app_service_plan`, `managed_identity`.

The list grows on-demand. See "How to add a resource type" below.

## Composition

A consumer reads outputs from this module and passes them as inputs to other modules:

```hcl
module "naming" {
  source   = "../../modules/foundation/naming"
  org      = "wsx"
  workload = "memberapi"
  env      = "prod"
  region   = "eastus"
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.names.resource_group
  location = "eastus"
  tags     = module.tags.tags # from foundation/tags (ADR 0010)
}
```

This module does not produce Azure resources; it produces the names other modules use.

## How to add a resource type

1. Identify Azure naming constraints for the resource (length, allowed characters, global uniqueness, casing).
2. Add the construction in `main.tf` `locals`. Use:
   - `parts_hyphen` for resources that allow hyphens.
   - `parts_compact` for resources that don't (storage accounts, container registries).
   - Custom construction if the resource has unusual constraints.
3. Add the entry to `local.names`.
4. Add a description row to this README.
5. Add an assertion to `tests/convention_compliance.tftest.hcl`.
6. Open a PR per [CONTRIBUTING.md](../../../CONTRIBUTING.md).

## Region abbreviations

Maintained in `main.tf`'s `local.region_abbreviations` map. Adding a region is a one-line PR. Unrecognized regions fall back to the unmodified region name.

## Constraints and gotchas

- **Storage account names are global.** Two accounts with the same name in different subscriptions collide. The convention reduces collision risk by including org/workload/env/region/instance, but does not eliminate it. Future enhancement: an optional `unique_suffix` flag that appends a 4-char hash of the subscription ID. Open a PR if you need it.
- **Length limits hash, not truncate.** Storage accounts cap at 24 chars; if `org` + `workload` + `env` + `region` + `instance` exceeds the cap, the compact form keeps a deterministic hash of the full identity in the name instead of silently truncating (truncation caused collisions between long workloads that shared a prefix). The `convention_compliance` test asserts the cap and the hash behavior.
- **Pure logic, no resources.** This module never calls a provider. `versions.tf` declares no `required_providers`. Plan and apply are fast and free.

## Why this module ships no `policy/` or `monitoring/`

It produces no Azure resources — there is nothing to govern with policy and nothing to alert on. The empty `ships` arrays in `manifest.yaml` reflect this. Per [AGENTS.md Hard Rule 1](../../../AGENTS.md), "ships its own observability and policy" applies to modules that produce auditable resources. This one does not, and that is documented in the contract.

## Cites

- Implements [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md): composition by outputs only.
- Aligns with [ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md): the `env` input vocabulary matches the tag taxonomy.
- Prevents the naming-chaos cousin of [AP-008](../../../docs/anti-patterns.md#ap-008--tag-chaos).
