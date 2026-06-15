# schemas/

The two machine-readable contracts a human authors against. The `.json` files are the
source of truth for fields and are enforced in CI; this README is orientation only and
deliberately does **not** restate every property — read the schema (each field carries an
inline `description`) and the governing ADR for that.

## `conformance-descriptor.schema.json` — what a deployable root declares

Every deployable root carries a `vitruvius.yaml` stating what kind of deployment it is; the
named profile's rules are then checked against its rendered plan ([ADR 0025](../docs/decisions/0025-deployment-conformance-and-platform-baseline.md)).
App teams write this when they onboard a workload.

```yaml
apiVersion: vitruvius.io/v1
kind: TerraformRoot
metadata: { name: member-api-prod, owner: member-services }
spec:
  scope: workload_resource_group        # ADR 0024 role vocabulary
  profile: regulated-workload/v1        # selects the plan-policy bundle in profiles/
  business-criticality: tier-1          # ADR 0010 vocabulary
  data-classification: restricted       # ADR 0010 vocabulary
  exceptions: []                        # ADR 0008 exemptions, if any
```

Authoritative live examples (validated against this schema in CI): every
[`examples/*/vitruvius.yaml`](../examples). `scripts/validate-roots.py` proves each root's
descriptor resolves; `scripts/evaluate-conformance.py` checks the profile against the plan.

## `module-manifest.schema.json` — the contract for a platform module

Every module carries a `manifest.yaml` declaring the meaning-level facts HCL can't express —
its inputs/outputs, AVM dependencies, the cross-cutting concerns it participates in, what
policy/monitoring it ships, and which ADRs and anti-patterns it cites ([ADR 0011](../docs/decisions/0011-module-manifest.md)).
Module authors write this; `scripts/validate-manifests.py` enforces that it agrees with the
code, and `catalog-info.yaml` is generated from it ([ADR 0016](../docs/decisions/0016-software-catalog-and-backstage-contract.md)).

```yaml
apiVersion: vitruvius.io/v1
kind: Module
metadata: { name: web-api-aks, area: workload-patterns, version: 0.1.0, status: experimental, owner: platform }
spec:
  inputs: [ ... ]        # mirrors variables.tf
  outputs: [ ... ]       # mirrors outputs.tf
  dependencies: { avm: [ ... ], repo: [] }   # repo deps forbidden — ADR 0004
  cross_cutting: { identity: true, observability: true, secrets: true, ... }
  ships: { policy: [ ... ], monitoring: [ ... ], runbooks: [] }
  cites: { principles: [ ... ], decisions: [ ... ], anti_patterns: [ ... ] }
```

Authoritative live examples: every [`modules/*/*/manifest.yaml`](../modules).
