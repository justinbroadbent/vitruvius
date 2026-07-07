# platform-services/aks-cluster — AI agent notes

Module-specific guidance for AI agents working in `modules/platform-services/aks-cluster/`. Read alongside [`README.md`](./README.md).

## What this module is

The platform-run AKS cluster. It is the producer end of the workload-identity seam: it emits `oidc_issuer_url`; `workload-patterns/web-api-aks` consumes it. The platform team runs clusters — developers never do.

## Anti-patterns specific to this module

- **DO NOT** expose the hardened posture as inputs. `enable_private_cluster`, `disable_local_accounts`, `enable_rbac`, `aad_profile.enable_azure_rbac`, `oidc_issuer_profile.enabled`, and `security_profile.workload_identity.enabled` are fixed in `main.tf`. A consumer who needs them different forks the module (ADR 0004); they do not get a flag.
- **DO NOT** add a `kubernetes` or `helm` provider, or any `kubernetes_*` / `helm_*` resources. Terraform stops at the Azure control plane (ADR 0026). Cluster-internal objects are the workload team's own delivery mechanism, not this module's Terraform. (Same rule as `web-api-aks`.)
- **DO NOT** add a `kube_admin_config` / admin-kubeconfig output or anything that surfaces a static credential. Local accounts are disabled on purpose (ADR 0009); access is Entra + Azure RBAC. `kubelet_identity` is fine — it is an identity reference, not a secret.
- **DO NOT** flip `enable_telemetry` on. Platform infrastructure does not send AVM usage telemetry, and the flag must stay off for `terraform test` to be hermetic.
- **DO NOT** call `foundation/naming` or `foundation/tags` from inside this module. In-repo module imports are forbidden (ADR 0004, `dependencies.repo: maxItems: 0`).

## AVM module pinning

The AVM managed-cluster module is pinned at `0.6.1` in `main.tf` (exact, not `~>`). It is one of the largest and fastest-moving AVM modules; its input surface (`default_agent_pool`, `network_profile`, `aad_profile`, `oidc_issuer_profile`, `security_profile`, `api_server_access_profile`) changes between minor versions. It is **azapi-based**: the cluster is an `azapi_resource`, so it takes `parent_id` (a resource group resource ID), not `resource_group_name`, and misnamed optional object attributes (e.g. `azure_rbac_enabled` instead of `enable_azure_rbac`) are **silently dropped** by Terraform's type conversion rather than rejected — check attribute names against the pinned version's `variables.tf`, not against azurerm resource schemas. When upgrading:

1. Pin to the exact patch version tested against.
2. Re-run `terraform test`; watch for input renames (the nested object keys move).
3. Update `manifest.yaml` `dependencies.avm` version to match.

## Test approach

`input_validation.tftest.hcl` is the robust workhorse: every `run` overrides one variable to an invalid value with `command = plan` and `expect_failures`. These fail during variable evaluation, before any provider call, so they hold regardless of which providers the AVM module pulls in.

`contract_compliance.tftest.hcl` runs `command = apply` under `mock_provider` blocks for **both azurerm and azapi** and asserts the documented outputs surface. The azapi mock needs realistic defaults (a well-formed managed-cluster resource ID, an `output` payload with the OIDC issuer, a base64 kubeconfig from the kubeconfig action) — the provider's auto-generated mock values are not valid resource IDs and downstream resources reject them. `azapi` is declared in `versions.tf` so the mock binds to `Azure/azapi` instead of the nonexistent `hashicorp/azapi`.

## When to extend vs add a module

Extend this module for cluster *configuration* (a new tunable that does not weaken the posture, an additional system-pool knob). Add a sibling module when the shape differs materially — for example a **user node pool** module for a workload class, or the **AKS-hardening policy initiative** (which belongs with `foundation/policy-baseline`, not here). The estate runs few clusters and few cluster modules; resist multiplying them.
