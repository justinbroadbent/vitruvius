# platform-services/aks-cluster

A **platform-run** AKS cluster, built on the [AVM managed-cluster module](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm/latest) ([ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md)). The platform team runs the clusters; workloads federate into them.

## What this module is (and isn't)

**Is:** the hardened cluster the estate's containerized workloads run on. The security posture is opinionated and **not tunable through inputs**:

- **Private API server** — no public control plane ([ADR 0018](../../../docs/decisions/0018-network-topology-hub-spoke.md)).
- **Entra ID + Azure RBAC**, with **local accounts disabled** — there is no shared cluster password; access is an Entra group with an Azure RBAC role ([ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md)).
- **OIDC issuer + workload identity on** — this is the seam. A workload created by [`workload-patterns/web-api-aks`](../../workload-patterns/web-api-aks) federates to this cluster's `oidc_issuer_url` with **no shared secret**.
- **Diagnostics to the substrate** Log Analytics workspace ([ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md)).
- **Automatic patching** — node-image always, Kubernetes version on a channel.

A consumer who needs a different posture **forks the module** ([ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md)); they do not get there by flipping an input.

**Isn't:**
- **Kubernetes resources** (namespaces, deployments, RBAC bindings). The provider surface is azurerm-only; cluster-internal objects are the workload team's GitOps, not Terraform's.
- **Node pools for workloads.** This ships one zone-redundant *system* pool. User pools per workload class are a follow-up once a real workload defines the shape.
- **The AKS-hardening Azure Policy initiative.** The cluster's posture is enforced by its own configuration here; an estate-wide "all clusters must be private / RBAC-only" Deny initiative belongs with `foundation/policy-baseline` and is a deliberate next increment (this module ships no `policy/` yet, and `manifest.yaml` says so).

## Composition

Per [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md), the cluster composes with the foundation modules **at the consumer boundary** (the reference landing zone), and its `oidc_issuer_url` output is the input to every workload:

```hcl
module "aks" {
  source = "../../modules/platform-services/aks-cluster"

  name                       = module.naming.names.aks_cluster
  resource_group_id          = azurerm_resource_group.platform.id
  location                   = "eastus"
  node_subnet_id             = module.hub.subnet_ids["aks"]
  log_analytics_workspace_id = module.observability_substrate.log_analytics_workspace_id
  admin_group_object_ids     = var.platform_admin_group_object_ids
  tags                       = module.tags.tags
}

# A workload then federates into the cluster — no secret crosses the boundary:
module "memberapi" {
  source              = "../../modules/workload-patterns/web-api-aks"
  aks_oidc_issuer_url = module.aks.oidc_issuer_url
  # ...
}
```

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Cluster name from foundation/naming. Validated to start with `aks-`. |
| `resource_group_id` | string | yes | Resource ID of the RG where the cluster is created (the AVM module is azapi-based and takes a parent resource ID, not a name). |
| `location` | string | yes | Azure region. |
| `node_subnet_id` | string | yes | Subnet the system node pool joins (platform network, ADR 0018). |
| `log_analytics_workspace_id` | string | yes | Substrate LAW the cluster's diagnostics route to (ADR 0005). |
| `admin_group_object_ids` | `list(string)` | yes | Entra groups granted cluster-admin via Azure RBAC. Required — local accounts are disabled. |
| `tags` | `map(string)` | yes | Tag map from foundation/tags; the five required keys are enforced. |
| `kubernetes_version` | string | no | Minor version (e.g. `1.30`); null = region default. |
| `system_node_pool` | object | no | vm_size / node_count / autoscaler min+max / zones / max_pods / OS disk. Zone-redundant 3-node default. |
| `network` | object | no | Policy engine + CIDRs. Fixed to Azure CNI overlay. |
| `private_dns_zone_id` | string | no | Private DNS zone for the API server (hub's zone); null = AKS-managed. |
| `authorized_ip_ranges` | `list(string)` | no | Extra API-server IP allow-list on top of the private endpoint. |
| `user_assigned_identity_id` | string | no | Control-plane UAI; null = system-assigned. |
| `upgrade_channel` | string | no | Kubernetes auto-upgrade channel (default `stable`). |

## Outputs

| Name | Type | Description |
|---|---|---|
| `cluster_id` | string | Managed cluster resource ID. |
| `cluster_name` | string | Managed cluster name. |
| `oidc_issuer_url` | string | **The seam** — pass to `web-api-aks` as `aks_oidc_issuer_url`. |
| `node_resource_group_name` | string | Auto-created node RG (`MC_*`). |
| `kubelet_identity` | object | Kubelet identity (clientId/objectId/resourceId) for downstream grants (AcrPull, etc.). |

## Cites

- Implements [ADR 0026](../../../docs/decisions/0026-platform-run-clusters-and-control-plane-boundary.md) (clusters are platform-run; Terraform stops at the Azure control plane).
- Implements [ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md) (AVM-first for the cluster primitive).
- Honors [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md) (diagnostics to the substrate LAW).
- Honors [ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md) (local accounts disabled; workload identity is the access model).
- Honors [ADR 0018](../../../docs/decisions/0018-network-topology-hub-spoke.md) (private cluster in the platform network).
- Prevents [AP-006 (secret rotation toil)](../../../docs/anti-patterns.md#ap-006--secret-rotation-toil) — no cluster password to rotate.

## Why this module ships no policy or monitoring (yet)

`experimental`. The cluster's hardened posture is enforced by its own configuration; the estate-wide AKS-hardening **policy initiative** (private-cluster-required, local-accounts-disabled, RBAC-required) is a deliberate next increment under `foundation/policy-baseline`. No alert rules ship yet either — paging thresholds for a cluster (node-not-ready, API-server latency) wait on a real operating signal. The empty `ships` arrays in `manifest.yaml` say so honestly, per [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md).
