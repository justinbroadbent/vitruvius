# foundation/identity

Platform-baseline user-assigned managed identities. **Identity primitives only** — no role assignments, no custom role definitions, no federated credentials, no PIM, no Conditional Access. See "What this module deliberately does NOT do" below.

This module establishes the platform identity layer with a deliberately small v0.1.0 surface. Custom roles and the broader RBAC strategy are deferred until the team has made those decisions explicitly — making them up here would put assumptions into the load-bearing path.

## What ships

Two user-assigned managed identities:

| Identity | Default name | Purpose |
|---|---|---|
| `deploy` | `id-platform-deploy` | The identity CI/CD assumes when applying platform Terraform. |
| `policy_remediation` | `id-platform-policy-remediation` | Available for Azure Policy assignments using `DeployIfNotExists` or `Modify` effects, in place of per-assignment `SystemAssigned` identities. |

The `policy_remediation` UAI is a forward-looking primitive — currently the policy-shipping modules in this repo (`foundation/tags`, `foundation/diagnostic-settings`, `workload-patterns/web-api-aks`) use `SystemAssigned` identities per-assignment. Centralizing on this UAI is a future-PR decision (audit consolidation vs single-point-of-compromise tradeoff).

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `resource_group_name` | string | yes | RG where both UAIs are created. |
| `location` | string | yes | Azure region for the UAIs. |
| `tags` | `map(string)` | yes | Tag map from `foundation/tags`. The five required keys from ADR 0010 are validated. |
| `deploy_identity_name` | string | no | Override for the deploy UAI's name. Default `id-platform-deploy`. |
| `policy_remediation_identity_name` | string | no | Override for the policy-remediation UAI's name. Default `id-platform-policy-remediation`. |

## Outputs

Each identity output is an object with `id`, `principal_id`, `client_id`, `tenant_id`, `name`:

| Name | Description |
|---|---|
| `deploy` | Deploy UAI metadata. |
| `policy_remediation` | Policy-remediation UAI metadata. |

## Composition

```hcl
module "tags" {
  source = "../../modules/foundation/tags"
  # ... required tag inputs
}

module "identity" {
  source = "../../modules/foundation/identity"

  resource_group_name = "rg-platform-prod"
  location            = "eastus"
  tags                = module.tags.tags
}

# Grant the deploy UAI Contributor on a target subscription. Role assignments
# happen at the consumer boundary, not inside this module.
resource "azurerm_role_assignment" "deploy_contributor_on_workload_sub" {
  scope                = "/subscriptions/<workload-sub-id>"
  role_definition_name = "Contributor"
  principal_id         = module.identity.deploy.principal_id
}
```

## What this module deliberately does NOT do

These are deferred to future work, not omissions:

- **Custom Azure RBAC role definitions.** Author's note: identity is the team's weakest skill area as of v0.1.0, and inventing custom roles would put unverified assumptions into the load-bearing path. When custom roles are added, they will be a deliberate ADR with each role's actions, notActions, and dataActions reviewed against a specific use case.
- **Role assignments.** Assignments are environment-specific (which subscription, which scope, which role). They live at the consumer boundary, not inside the foundation module.
- **Additional platform identities** (e.g., `id-platform-observability`, `id-platform-backup`). These will be added when concrete consumers exist. Speculative identities accumulate as drift.
- **Federated credentials** (GitHub Actions OIDC, Azure DevOps OIDC). When the team decides which CI/CD platform is canonical, federation patterns can ship. AKS-specific workload-identity federation lives in `workload-patterns/web-api-aks`.
- **Privileged Identity Management (PIM)** eligibility configuration. PIM requires org-level decisions about approval flows, MFA requirements, and activation durations. A future module (likely `platform-services/pim` or similar) will own this.
- **Conditional Access policies.** Same reason as PIM — org-level decisions that the platform module shouldn't presume.
- **Break-glass account infrastructure** per ADR 0007. Break-glass deserves its own module with associated monitoring and auto-PR-back wiring.

The module being small in v0.1.0 is the design, not an oversight. The AGENTS.md elaborates on when to add to it (and when to push back on adding speculative identities).

## Cites

- Honors [ADR 0009](../../../docs/decisions/0009-secrets-ephemeral-by-default.md) — managed identities are the substitute for static client secrets.
- Prevents [AP-006 (secret rotation toil)](../../../docs/anti-patterns.md#ap-006--secret-rotation-toil) by establishing managed-identity primitives the rest of the platform consumes.
