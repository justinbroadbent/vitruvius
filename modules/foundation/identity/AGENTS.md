# foundation/identity — AI agent notes

Module-specific guidance for AI agents working in `modules/foundation/identity/`. Read alongside [`README.md`](./README.md).

## What this module is

The platform identity layer's seed. v0.1.0 ships **two user-assigned managed identities and nothing else** — no role assignments, no custom roles, no federation, no PIM, no Conditional Access. The deliberate minimality is the design. Read the README's "What this module deliberately does NOT do" before proposing changes.

This module is unusual in the foundation layer in that it ships **no policy** (`ships.policy: []` in the manifest). That's intentional — identity primitives don't have a policy story until role-assignment policies and managed-identity-vs-service-principal policies are in scope. Both are deferred.

## Why the v0.1.0 scope is what it is

The repo's owner is honest about identity being their weakest skill area. The v0.1.0 scope reflects "what is uncontroversially correct without making opinionated RBAC decisions":

- A deploy UAI: every IaC platform needs one; no controversy.
- A policy-remediation UAI: every platform with `DeployIfNotExists` policies needs an identity for them; the centralized-vs-per-assignment choice is exposed as a forward-looking primitive consumers can opt into.

Custom roles, role assignments, additional UAIs, federation patterns, PIM, Conditional Access, and break-glass are all out of scope at v0.1.0 because they require real org-level decisions that haven't been made. **Adding any of them speculatively puts unverified assumptions into the load-bearing path.** That's a worse failure mode than the module being small.

When the org makes these decisions, they will arrive as deliberate PRs, each with its own ADR (or amendment to an existing ADR).

## Anti-patterns specific to this module

- **DO NOT** add custom role definitions speculatively. Every custom role is an opinionated set of `actions`/`notActions`/`dataActions` claims that must be defended in audit. If a role is needed, that's an ADR conversation, not a flag on this module.
- **DO NOT** add `azurerm_role_assignment` resources inside this module. Role assignments are environment-specific (which scope, which role, which principal). They belong at the consumer boundary. Adding them inside this module produces wrong assignments for some environments.
- **DO NOT** add a `federated_credentials` input. Federation is per-workload (AKS workload identity is in `workload-patterns/web-api-aks`) or per-CI/CD-platform (a future module). Generic federation in a foundation module fragments the federation story.
- **DO NOT** add additional UAIs without a concrete consumer. "We might need an observability identity someday" is not a reason; "the LAW collector module created today references this" is. Speculative identities accumulate as drift; deleting them later requires verifying nothing started using them in the meantime.
- **DO NOT** add a `policy_remediation_role_scope` or similar input that has the module assign the policy-remediation UAI a role. The role assignments depend on which policy types remediation covers — that's a per-policy-initiative decision, not a foundation concern.
- **DO NOT** flip the module to use a `for_each` over a `map(object)` of identities. That parameterization makes it possible to "just add another identity" without an ADR, undoing the deliberate scope discipline.

## When to add to this module (and when to make a new module)

Add to this module when:
- A concrete consumer in the repo references an identity that doesn't yet exist (e.g., a new platform service that legitimately needs its own UAI).
- The platform's RBAC strategy advances and a small, uncontroversial custom role is decided (e.g., `platform-readonly`). Even then, the role definition lands here only if it's truly platform-baseline; workload-specific roles belong with their workload patterns.

Make a new module when:
- The scope becomes opinionated (PIM, Conditional Access, break-glass, federation).
- The identity primitive depends on substantial external infrastructure (e.g., a break-glass module needs monitoring, auto-PR-back, and alerting — not a foundation concern).
- The new module would have its own clear contract distinct from "platform-baseline managed identities."

## Test approach

Tests use `mock_provider "azurerm"` with a single `mock_resource` override for `azurerm_user_assigned_identity` (returning a properly-shaped Azure resource ID and the four standard ID fields). All assertions are on plan/apply outputs; no Azure credentials needed.

The `outputs_have_documented_shape` assertion is the contract test — if the output object structure changes, downstream consumers (which reference `module.identity.deploy.principal_id` etc.) break. Treat output shape changes as breaking changes requiring a major version bump per the manifest's `metadata.version` semver.

## Validation expectations

CI runs (or will run, once the workflow is in place):

- `terraform fmt`
- `terraform validate`
- `terraform test` — `identity_compliance.tftest.hcl` (8 assertions)
- Manifest schema validation against `schemas/module-manifest.schema.json`
- Manifest-vs-code coherence (inputs, outputs match what's in code)
