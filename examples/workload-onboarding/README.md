# examples/workload-onboarding

The **app team's side** of the golden path. `examples/reference-landingzone` shows what the *platform team* deploys; this example shows what a *workload team* copies into its own repository to onboard a web API onto the [`web-api-aks`](../../modules/workload-patterns/web-api-aks/) pattern.

The fictional team here is `payments-team`, onboarding a workload called `paylink`.

## What you get vs. what you own

| The pattern hands you | You still own |
|---|---|
| A passwordless workload identity, federated to your Kubernetes ServiceAccount (ADR 0009) | Creating that ServiceAccount with the matching annotations (step 5) |
| A private-only Key Vault your identity can read, wired through a private endpoint | Your application code, container image, and Kubernetes manifests |
| Diagnostics routed to the platform observability substrate (ADR 0005) | Your SLOs and error budgets (ADR 0014) — the platform built the instruments; the numbers are yours |
| A KV-hardening policy bundle, named after *your* vault, observing in Audit mode (ADR 0008) | Your RTO/RPO declarations and restore drills (ADR 0015) |
| Conformant names and tags via `foundation/naming` and `foundation/tags` | Your resource group and your state file (ADR 0004 / 0017) |

## The onboarding, step by step

1. **Copy this directory** into your own repository as your environment root. One root per environment; one state file per root (ADR 0017).
2. **Collect the platform-published facts** — every variable in `variables.tf` is one. The platform team hands you the substrate workspace ID, the AKS cluster's OIDC issuer URL, your spoke's private-endpoint subnet, and the hub's Key Vault DNS zone. They arrive as *values* (outputs of the platform's roots) — you never read the platform's state.
3. **Fill in your own facts** — team alias, cost center, data classification, criticality tier, namespace, ServiceAccount name. The vocabularies are validated at plan time (ADR 0010).
4. **Open the PR.** Your pipeline plans it; review is the approval (ADR 0007); after merge it applies with OIDC federation — no stored credentials (ADR 0020).
5. **Wire the Kubernetes side.** Create the ServiceAccount in your namespace with the two annotations (`azure.workload.identity/client-id` from this root's output, `azure.workload.identity/tenant-id`), set `serviceAccountName` on your pods, and label the pod template `azure.workload.identity/use: "true"`. Get any of these wrong and federation **fails closed** — there is no fallback secret.
6. **Confirm the policy story.** Your vault's hardening initiative starts in Audit/DoNotEnforce. Promotion to Deny is a later PR citing audit-mode evidence — see the module README.

## How you consume the modules

In this example the `source` addresses are relative paths, because the example lives in the same repository as the modules. **A real team pins a release:**

```hcl
module "web_api" {
  source = "git::https://<host>/<org>/vitruvius.git//modules/workload-patterns/web-api-aks?ref=v0.1.0"
  # ...
}
```

The consumption contract:

- **Pin a tag, never a branch.** A branch reference floats; a tag is an immutable, reviewable upgrade. Each module's `manifest.yaml` carries its `metadata.version`; repository tags are the distribution mechanism.
- **Upgrades are deliberate PRs.** Bump the `ref`, read the module's changelog/diff, plan, review. The pattern's inputs are its contract — additions are backward-compatible; anything else is a version bump you opt into.
- **A private module registry is the v0.2+ shape** once there are enough consumers for discovery to matter — the same trigger discipline as the Backstage portal (ADR 0016). Moving from git refs to a registry changes the `source` string, nothing else.

## Deviating

If this pattern doesn't fit your workload, you don't fight the platform — you document the deviation: a short ADR identifying the six cross-cutting concerns you're taking ownership of, with platform and security sign-off. See [`docs/golden-paths.md`](../../docs/golden-paths.md). Repeated deviations in the same direction are treated as feedback about the pattern.

## Cites

- [ADR 0004](../../docs/decisions/0004-composition-by-output-data.md) — this root is the composition boundary; platform facts arrive as values.
- [ADR 0009](../../docs/decisions/0009-secrets-ephemeral-by-default.md) — workload identity; no static secrets anywhere in this file.
- [ADR 0010](../../docs/decisions/0010-tag-taxonomy.md) — the tag inputs and their vocabularies.
- [ADR 0017](../../docs/decisions/0017-terraform-state-and-backend.md) — one state file per workload per environment.
- [ADR 0018](../../docs/decisions/0018-network-topology-hub-spoke.md) — where the subnet and DNS zone come from.
- [ADR 0024](../../docs/decisions/0024-landing-zone-binding-and-scope-vocabulary.md) — the environment subscription this root deploys into.
