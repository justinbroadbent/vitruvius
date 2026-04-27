# policies/

Estate-wide Azure Policy assignments mapped to compliance frameworks. Policies that are **per-module** (i.e., govern resources a specific module produces) ship inside that module's `policy/` directory per [ADR 0003](../docs/decisions/0003-modules-ship-policy-and-monitoring.md). Policies in **this** directory are the cross-cutting ones — regulatory baselines, organization-wide controls, and policies that don't have a single owning module.

**Status: deferred.** No policy bundles ship yet.

The v0.x scope is [`ncua-glba/`](./ncua-glba/) — Azure Policy as code mapped to the NIST CSF subcategories and GLBA Safeguards Rule sections relevant to credit unions.

PCI is intentionally out of scope per the repo's overall posture (see [`README.md`](../README.md)).

Policies in this directory follow the same Audit-before-Deny lifecycle as module-shipped policies per [ADR 0008](../docs/decisions/0008-audit-before-deny-policy-lifecycle.md). The expected assignment scope is the platform management group; per-environment overrides happen at the consumer boundary, not in the policy bundle itself.
