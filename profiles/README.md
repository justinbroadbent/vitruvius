# profiles/

Conformance profiles (ADR 0025). A deployable root declares one in its `vitruvius.yaml` descriptor; the profile's rules are checked against the root's rendered Terraform plan before its change merges.

A profile is a named, versioned bundle of rules. Each rule names the resource types it applies to and a single property assertion, and cites the compliance control it supports ([ADR 0021](../docs/decisions/0021-ncua-glba-control-mapping-contract.md)). The rules assert **real planned properties** — `public_network_access_enabled`, `https_only`, `location` — not which modules a root happens to call, so a module cannot satisfy a rule by name alone (ADR 0025 §3).

| Profile | For | Rules |
|---|---|---|
| `platform-baseline/v1` | the platform foundation root | approved regions, no public blob |
| `regulated-workload/v1` | an internal workload handling member NPI | Key Vault / App Service no-public-access, App Service HTTPS-only, no public blob, approved regions |

## How a rule is evaluated

`scripts/evaluate-conformance.py` collects every resource from a `terraform show -json` plan (root and child modules), and for each rule checks the resources of the named types. A resource that lacks the asserted field is treated as **not applicable** to that rule, not as a failure. A descriptor `exceptions` entry waives a named rule, pointing at an [ADR 0008](../docs/decisions/0008-audit-before-deny-policy-lifecycle.md) exemption.

## What is built, and what is not

The descriptor schema, the profiles, and the evaluator are built and exercised in CI against plan fixtures (`scripts/conformance/fixtures/`). What is **not** yet built is the wiring that feeds a *real* rendered plan into the gate on every pull request — that lives in the deployment pipeline ([ADR 0020](../docs/decisions/0020-cicd-azure-devops-pipelines.md)), which is itself a planned control. See `docs/IMPLEMENTATION-STATUS.md`.
