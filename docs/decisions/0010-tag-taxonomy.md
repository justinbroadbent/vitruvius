---
id: 10
title: Tag taxonomy is small, mandatory, vocabulary-controlled, operational
status: accepted
date: 2026-04-26
categories: [foundation, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-008]
cites_adrs: [ADR-0003, ADR-0008]
---

# ADR 0010 — Tag taxonomy is small, mandatory, vocabulary-controlled, operational

## Context

A **tag** is a label attached to a cloud resource (`owner=payments-team`). [AP-008 — Tag chaos](../anti-patterns.md#ap-008--tag-chaos) is what free-form tagging becomes: the same idea spelled five ways, so cost-by-team reporting turns into manual work, policy targeting can't trust the tags, lifecycle automation can't use them as routing keys, and removing a tag breaks something nobody can identify.

Tags are a schema — a strict format, like the required fields on a form. Without enforcement, the schema rots. The fix is a small required tag set, **vocabulary-controlled** values (only values from a fixed, spell-checked list are accepted), automated enforcement, and operational hooks that make the tags do real work.

## Decision

A small, mandatory, vocabulary-controlled tag set governs every taggable resource in the estate.

### Required tags (5)

| Tag | Purpose | Example values |
|---|---|---|
| `owner` | accountable team alias | `platform-team`, `member-services` |
| `env` | deployment environment | `prod`, `staging`, `dev`, `sandbox` |
| `cost-center` | financial allocation | `cc-1001`, `cc-2002` |
| `data-classification` | data sensitivity | `public`, `internal`, `confidential`, `restricted` |
| `business-criticality` | recovery priority | `tier-0`, `tier-1`, `tier-2`, `tier-3` |

### Optional tags (vocabulary-controlled)

- `app` — application alias (free string, but it must match an entry in the Backstage catalog, our service directory)
- `component` — sub-component within an app
- `lifecycle` — `stable`, `experimental`, `deprecated`

### Forbidden

- Free-form tags outside the taxonomy.
- Person-name tags (`owner=jane.doe`); ownership is at team granularity — people change roles, teams persist.
- `temp`, `test`, `delete-me` — it is never temporary.
- Inconsistent capitalization or spelling. `env=prod` is the only correct form; `env=Prod`, `Env=production`, `environment=PROD` are all rejected.

### Enforcement

Enforcement is automated through **Azure Policy** (Azure's built-in rule-enforcement system):

- The **`modify` effect** automatically fills in a required tag on a child resource by inheriting it from the resource group or subscription when it is missing.
- The **`audit` and `deny` effects** govern allowed values. The lifecycle in [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) applies — new value restrictions ship in watch-only `Audit` mode before being promoted to blocking.
- The **`modules/foundation/tags`** module ships the policy assignments and the canonical vocabulary. Adding a value is a PR to the module.

### Operational hooks (tags do real work, or they don't exist)

Every tag drives some automated behavior — a tag that controls nothing isn't allowed to exist:

- `data-classification=restricted` triggers customer-managed keys (encryption keys we hold rather than Microsoft), private endpoints (no public network path), and stricter diagnostic-setting retention.
- `business-criticality=tier-0` triggers stricter SLA monitoring, geo-redundancy requirements, and PIM-only change paths (changes require checked-out, logged admin access).
- `owner` drives alert routing (via the Backstage catalog), access-review notifications, and the quarterly review cadence — it decides who gets paged.
- `lifecycle=experimental` triggers a 30-day TTL job that warns the owner and then cleans up.
- `env` shapes the policy enforcement tier (`Audit` in dev/sandbox, `Deny` in prod).
- `cost-center` enables automated cost allocation reports without per-resource tagging review.

### Governance

Tag taxonomy changes go through ADR. Adding a new *required* tag is a breaking change managed deliberately — existing resources need a back-fill plan (retro-tagging everything already deployed) before the new requirement promotes from `Audit` to `Deny`. Adding a new *value* to an existing vocabulary is a normal change.

## What this does not decide

- **The concrete data** — actual `cost-center` codes, team aliases in `owner`, and `app` names are org data supplied by the adopter, not platform decisions.
- **Whether more keys graduate to required later** — that is governed through ADR (with an estate-wide back-fill), not pre-decided.
- **The mechanics of the operational hooks** — the TTL job, alert routing, and cost-allocation reports referenced above depend on the substrate and the Backstage catalog; their implementations are follow-ups, not settled here.

## Reversibility

The two halves of this decision sit on opposite sides of the door, and the split *is* the design:

- **The set of required keys: load-bearing (one-way door).** Once resources are tagged and policies, cost reports, and lifecycle automation all target those keys, renaming or removing a key breaks policy targeting, cost allocation, and cleanup jobs across the whole estate, and forces an estate-wide back-fill. The ADR already names "add a required tag" as a breaking change; *removing or renaming* one is worse. Commit to the keys carefully.
- **The vocabulary of allowed values: cheap to change (two-way door).** Adding an allowed value is "a PR to the `foundation/tags` module," shipped through Audit-before-Deny (ADR 0008) — additive, low blast radius. Iterate freely here.

> **In plain terms:** the tag *keys* are like the printed fields on a shipping label — change those and every scanner in the warehouse breaks. The allowed *values* are like adding a new zip code to the list — routine. That asymmetry is the contract-vs-specifics line: the **keys** are the contract, the **values** are tunable.

## Consequences

**Positive.**

- Cost allocation is automatic and accurate; no manual reconciliation.
- Policy targeting is reliable because values are vocabulary-controlled.
- Lifecycle automation works because tags can be queried.
- Operational tooling has a stable schema to build on.
- New tags must justify themselves by doing operational work, which keeps the taxonomy small.

**Negative — and accepted.**

- Required tags must be supplied at create time; this adds friction at the moment of creation. The friction is paid once per resource and pays back at every cost report, audit, and policy targeting.
- Vocabulary-controlled values mean teams cannot invent local conventions. We accept the constraint; the global taxonomy is more valuable than per-team flexibility.
- Adding a new required tag is expensive (back-fill across the estate). We accept the expense; the alternative is taxonomy drift.

## Cites

- [AP-008](../anti-patterns.md#ap-008--tag-chaos) — what this ADR prevents.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — tag policy travels with the foundation/tags module.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — value restrictions follow Audit-before-Deny.
