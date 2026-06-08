# examples/reference-landingzone

A platform landing zone composed from the foundation and platform-services modules. It is the worked demonstration of `docs/composition.md`: a consumer root that wires modules together by passing each module's outputs into the next, at the consumer boundary, with no module importing another ([ADR 0004](../../docs/decisions/0004-composition-by-output-data.md)).

The values in this root are illustrative. Copy it, substitute your own org code, region, management group, and subscription, and it becomes a real environment root.

## What it composes

```
naming ─┐
        ├─► resource group (rg-…)
tags ───┤
        ├─► identity            (deploy + policy-remediation UAIs)
        ├─► observability-substrate ──► log_analytics_workspace_id ─┐
        │                                                           │
        └─► diagnostic-settings ◄────────────────────────────────── ┘
                                  (routes the estate's diagnostic
                                   settings to that workspace)
```

## The seams

Each row is an output of one module wired into the input of another — composition by output data:

| Producer | Output | Consumer | Input |
|---|---|---|---|
| `naming` | `names.resource_group` | `azurerm_resource_group` | `name` |
| `naming` | `names.log_analytics_workspace` | `observability-substrate` | `log_analytics_workspace_name` |
| `naming` | `names.application_insights` | `observability-substrate` | `application_insights_name` |
| `tags` | `tags` | every module | `tags` |
| `observability-substrate` | `log_analytics_workspace_id` | `diagnostic-settings` | `log_analytics_workspace_id` |

The substrate → diagnostic-settings seam is the point of the example: the substrate produces the workspace, and the diagnostic-settings initiative routes the estate's resources to it — the two halves of [ADR 0005](../../docs/decisions/0005-observability-substrate-and-signal-parity.md) wired together.

## Using it

```sh
export ARM_SUBSCRIPTION_ID=<your subscription>
terraform init
terraform plan  -var 'org=wsx' -var 'env=dev' -var 'location=eastus' \
                -var 'platform_management_group_id=/providers/Microsoft.Management/managementGroups/<your-platform-mg>'
terraform apply
```

The defaults in `variables.tf` let it `init` and `validate` with no input; `plan`/`apply` need a real subscription and management group.

## What it does not include

- **Networking** — the `hub` module is not built yet. When it ships, the spoke wiring (hub outputs → workload inputs) joins this root.
- **Workload patterns** — this is the platform landing zone. A workload (e.g. `web-api-aks`) is a separate root that consumes this one's outputs (the workspace ID, the identities) at its own boundary.
- **Multiple environments** — one `dev` landing zone is shown. `staging` and `prod` are the same root with different inputs, each in its own subscription ([ADR 0024](../../docs/decisions/0024-landing-zone-binding-and-scope-vocabulary.md)).
