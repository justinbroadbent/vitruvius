# workload-patterns/web-api-aks

Workload pattern for a containerized web API running on AKS. Provisions the **Azure-side** primitives the application needs — workload identity, Key Vault, federated credential, and the policy initiative that hardens them — so an app team can focus on the application itself.

## What this module is (and isn't)

**Is:** the cross-cutting wiring an HTTP-API workload needs on Azure to be secure, observable, and policy-governed by default. Identity is workload-identity-federated (no static secrets per [ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md)). Secrets live in a per-workload Key Vault that the workload's UAI has `Key Vault Secrets User` on. Diagnostic logs flow to the platform LAW per [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md). KV hardening is enforced by the policy initiative this module ships.

**Isn't:**
- The AKS cluster itself. Today the cluster is the consumer's to provide; this module takes its OIDC issuer URL as input. A platform AKS baseline (cluster module plus its ADR) is future work.
- Kubernetes resources (namespace, deployment, service, ingress). The app team owns these. The `service_account_annotations` output tells the app team which annotations to put on their `ServiceAccount` to activate workload-identity federation.
- A multi-cluster orchestrator. One invocation = one workload's primitives on one cluster.

The deliberate scope keeps the module's provider surface to azurerm-only and its contract to "what does Azure need to know about this workload."

## Composition

Per [ADR 0004](../../../docs/decisions/0004-composition-by-output-data.md), this module composes with the foundation modules **at the consumer boundary**:

```hcl
module "naming" {
  source   = "../../modules/foundation/naming"
  org      = "wsx"
  workload = "memberapi"
  env      = "prod"
  region   = "eastus"
}

module "tags" {
  source               = "../../modules/foundation/tags"
  owner                = "member-services"
  env                  = "prod"
  cost_center          = "cc-2002"
  data_classification  = "confidential"
  business_criticality = "tier-1"
}

module "memberapi" {
  source = "../../modules/workload-patterns/web-api-aks"

  user_assigned_identity_name = module.naming.names.managed_identity
  key_vault_name              = module.naming.names.key_vault
  resource_group_name         = "rg-memberapi-prod"
  location                    = "eastus"
  tags                        = module.tags.tags

  aks_oidc_issuer_url      = data.azurerm_kubernetes_cluster.platform.oidc_issuer_url
  aks_namespace            = "memberapi"
  aks_service_account_name = "memberapi-sa"

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.substrate.id
}
```

The workload-pattern never imports the foundation modules. Names and tags are passed as data through the consumer.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `user_assigned_identity_name` | string | yes | Pre-computed UAI name from foundation/naming. Validated to start with `id-`. |
| `key_vault_name` | string | yes | Pre-computed KV name from foundation/naming. Validated to start with `kv-` and respect Azure's 24-char limit. |
| `resource_group_name` | string | yes | RG for the workload's UAI and KV. |
| `location` | string | yes | Azure region. |
| `tags` | `map(string)` | yes | Tag map from foundation/tags. The five required keys from ADR 0010 are enforced by validation. |
| `aks_oidc_issuer_url` | string | yes | OIDC issuer URL of the AKS cluster (read from the cluster resource). Used to build the federated credential. |
| `aks_namespace` | string | yes | Kubernetes namespace where the workload's pods run. |
| `aks_service_account_name` | string | yes | Kubernetes ServiceAccount the workload's pods authenticate as. |
| `log_analytics_workspace_id` | string | yes | Resource ID of the platform LAW per ADR 0005. |
| `key_vault_sku` | string | no | `standard` (default) or `premium`. |
| `key_vault_soft_delete_retention_days` | number | no | 7–90 (default 90). Auditors expect the maximum. |
| `policy_assignment_scope` | string | no | Scope at which the initiative is assigned — a subscription (`/subscriptions/{guid}`) or resource group (`/subscriptions/{guid}/resourceGroups/{name}`) ID; the value is the actual scope. When null, no assignment is created — useful when a higher scope handles assignment. |
| `policy_enforcement_mode` | string | no | `DoNotEnforce` (default; Audit-before-Deny per ADR 0008) or `Default`. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `workload_identity_client_id` | string | UAI client ID. Annotate the K8s ServiceAccount with this. |
| `workload_identity_principal_id` | string | UAI principal/object ID. For external role-assignment grants. |
| `workload_identity_id` | string | UAI resource ID. |
| `key_vault_id` | string | KV resource ID. |
| `key_vault_uri` | string | KV URI for application configuration. |
| `service_account_annotations` | `map(string)` | The two annotations the app team applies to the K8s ServiceAccount for workload-identity federation. |
| `policy_initiative_id` | string | Initiative resource ID (always created). |
| `policy_assignment_id` | string | Assignment ID; null when `policy_assignment_scope` was not supplied. |

## Workload identity contract

The federated credential's subject is built deterministically as:

```
system:serviceaccount:<aks_namespace>:<aks_service_account_name>
```

The app team must:

1. Create the Kubernetes `ServiceAccount` with the matching name in the matching namespace.
2. Apply the annotations from `output.service_account_annotations` to that ServiceAccount.
3. Set `serviceAccountName` on their workload's pods.
4. Label their pod template with `azure.workload.identity/use: "true"`.

If the app team gets any of those wrong, federation fails closed — the pod cannot acquire an Azure token. There is no "shared secret as a backup" path. This is the secrets-ephemeral-by-default contract per [ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md).

## What ships in `policy/`

Three policies, bundled into a per-workload `vitruvius-kv-hardening-<key-vault-name>` initiative. Names derive from the (globally unique) Key Vault name so two workloads in the same subscription cannot collide:

| File | Effect | Purpose |
|---|---|---|
| `keyvault-purge-protection-required.json` | `Audit` (parameterized) | Reject KVs without purge protection. Catches drift even though the AVM module defaults purge protection on. |
| `keyvault-rbac-authorization-required.json` | `Audit` (parameterized) | Reject KVs that use the legacy access-policy auth model. RBAC unifies KV access with the rest of Azure RBAC (PIM, conditional access). |
| `keyvault-diagnostic-settings-required.json` | `AuditIfNotExists` (parameterized) | Detect KVs without a diagnostic setting routing to the platform LAW. Per ADR 0005, audit logs must flow to the substrate. |

Per [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md), the initiative's effects start at `Audit` and the assignment defaults to `DoNotEnforce`. Promotion to `Deny` is a single assignment-time change: set `policy_effect = "Deny"` in a PR that cites audit-mode evidence.

The `keyvault-diagnostic-settings-required` policy uses `AuditIfNotExists`, not `DeployIfNotExists`. Reason: this module's deployment is the source of the diagnostic setting. The policy detects drift; it does not heal. Healing-by-policy obscures who actually deployed what.

## Why AVM for the Key Vault but not the UAI

Per [ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md), AVM-first for primitives. The Key Vault has enough cross-cutting concerns (network ACLs, diagnostic settings, role assignments, soft-delete tuning) that the AVM module pays for itself. The UAI is two arguments — using AVM for it would be ceremony. The federated identity credential has no AVM equivalent.

## What this module does NOT do (and why)

- **No Kubernetes resources.** Adding the kubernetes provider doubles the provider surface and forces every consumer to wire cluster credentials. Defer to v0.2 if a real consumer needs it; until then, the app team owns their YAML.
- **No APIM facade.** Cross-network HTTP exposure is a separate workload pattern (`workload-patterns/apim-bff`, deferred). Most workloads don't need APIM; pulling it into the default pattern would over-scope.
- **Private endpoints are the consumer's subnet, this module's wiring.** `public_network_access_enabled = false` plus default-Deny ACLs means the vault is reachable *only* through a private endpoint. The `private_endpoints` input passes through to the AVM module — supply at least one (subnet and private-DNS zone IDs come from the consumer's networking per ADR 0018), or the workload identity holds a role on a vault it cannot reach.
- **No conditional CMK by data-classification.** [ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md) calls for `data-classification=restricted` to trigger CMK; this module does not yet implement that. Tracked as a v0.2 enhancement.

## Cites

- Implements [ADR 0001](../../../docs/decisions/0001-iac-terraform-with-avm.md) (AVM-first for KV).
- Implements [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md) (KV diag settings + KV-hardening initiative ship with the module).
- Honors [ADR 0005](../../../docs/decisions/0005-observability-substrate-and-signal-parity.md) (diag logs to platform LAW).
- Honors [ADR 0008](../../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) (Audit + DoNotEnforce defaults).
- Honors [ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md) (workload identity, no static client secrets).
- Honors [ADR 0010](../../../docs/decisions/0010-tag-taxonomy.md) (validates required tag keys at the input).
- Prevents [AP-001 (bolted-on monitoring)](../../../docs/anti-patterns.md#ap-001--bolted-on-monitoring) and [AP-006 (secret rotation toil)](../../../docs/anti-patterns.md#ap-006--secret-rotation-toil).

## Why this module ships no monitoring (yet)

The module is `experimental`: the Key Vault's diagnostic logs already route to the substrate (the AVM `diagnostic_settings` block), but no alert rules or dashboards ship yet — alerting on vault access patterns is a v0.2 item once a real consumer defines what is worth paging on. The empty `ships.monitoring` array in `manifest.yaml` reflects this; per [ADR 0003](../../../docs/decisions/0003-modules-ship-policy-and-monitoring.md), an experimental module may ship no monitoring, but it must say so.
