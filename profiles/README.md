# profiles/

Conformance profiles (ADR 0025). A deployable root declares one in its `vitruvius.yaml` descriptor; the profile's rules are checked against the root's rendered Terraform plan, by `scripts/evaluate-conformance.py`, before its change merges.

A profile is a named, versioned bundle of rules. Rules check two things ADR 0025 cares about:

- **Completeness** — the "someone left a brick out" problem the ADR exists to close. `require_resource` asserts a capability is present (at least N of some resource types); `forbid_resource` asserts one is absent (e.g., a static client secret).
- **Correctness** — `assert_property` checks a real planned property (`public_network_access_enabled`, `https_only`, `location`). These **fail closed**: a targeted resource whose value is missing or unknown is a violation unless the rule sets `on_missing: skip` (used for wildcard rules like `location`, which legitimately don't apply to every resource).

Rules assert real planned resources and values, never which modules a root calls — a module cannot satisfy a rule by name. Each rule cites the compliance control it supports ([ADR 0021](../docs/decisions/0021-ncua-glba-control-mapping-contract.md)).

| Profile | For | Checks |
|---|---|---|
| `platform-baseline/v1` | the platform foundation root | approved regions, no public blob (platform-layer completeness rules are a follow-up) |
| `regulated-workload/v1` | an internal workload handling member NPI | **requires** a federated workload identity; **forbids** static client secrets; Key Vault / App Service no-public-access, App Service HTTPS-only, no public blob, approved regions |

## Exemptions

A descriptor `exceptions` entry waives a rule only when it references a record in [`policies/conformance-exemptions.yaml`](../policies/conformance-exemptions.yaml) that **exists, is owned, is unexpired, covers that exact rule, and corresponds to a rule the plan actually failed** ([ADR 0025](../docs/decisions/0025-deployment-conformance-and-platform-baseline.md) §4 / [ADR 0008](../docs/decisions/0008-audit-before-deny-policy-lifecycle.md)). A missing, expired, unowned, wrong-rule, or unused exemption waives nothing and is itself a finding. That registry is the reference stand-in for the ADR 0008 exemption store; in a live estate the source of truth is Azure Policy exemptions with native expiry.

## What is built, and what is not

The descriptor schema, the profiles, the evaluator (completeness + correctness + forbid rules + exemption lifecycle), and the plan fixtures are built and exercised in CI (`scripts/evaluate-conformance.py --self-test`). What is **not** yet built:

- **Live wiring.** Feeding a *real* rendered plan into the gate on every pull request needs the deployment pipeline ([ADR 0020](../docs/decisions/0020-cicd-azure-devops-pipelines.md)) to produce `terraform show -json` from an authenticated plan — itself a planned control.
- **Descriptor-driven classification/reliability.** ADR 0025 §5's rule that the descriptor *renders* the mandatory tags and a rule confirms the plan matches is not yet implemented.
- **Cross-root completeness.** `require_resource` only sees one root's plan, so it names what a root must create *itself*. `regulated-workload/v1` therefore assumes a **root-local** federated identity; a workload that consumes a platform-provided identity is a different shape and would use a future `regulated-workload-shared-identity/v1` profile. A capability a workload *consumes* from another root (a shared Key Vault, that platform identity) is out of a single plan's view; proving it needs the descriptor's `provides`/`requires` graph, which ADR 0025 defers — and it should return only when it can carry *evidence* (the provider's resource IDs, profile, and a digest showing the provider passed its own gate), not a bare claim. Relationship rules (diagnostics-per-resource, private-endpoint-per-resource) are deferred for the same reason.

See `docs/IMPLEMENTATION-STATUS.md` for the current per-ADR status.
