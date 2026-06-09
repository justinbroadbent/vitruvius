---
id: 11
title: Module manifest as the structured contract for every module
status: accepted
date: 2026-04-26
categories: [foundation, architecture, ai]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-009, AP-012]
cites_adrs: [ADR-0003, ADR-0004]
---

# ADR 0011 — Module manifest as the structured contract for every module

## Context

Modules in this repo are required to ship documentation, policy, monitoring, and tests alongside their Terraform code (per [ADR 0003](./0003-modules-ship-policy-and-monitoring.md)). They must compose by outputs only, without cross-module imports (per [ADR 0004](./0004-composition-by-output-data.md)). They cite anti-patterns and principles in prose docs.

This contract is currently expressed across multiple files in mixed formats: prose `README.md`, prose `AGENTS.md`, HCL variable declarations, JSON policy assignments, JSON workbook definitions, HCL test files. AI agents, the Backstage developer portal, auditors, and humans navigating the repo all have to answer the same questions:

- What does this module do at the abstraction level it claims?
- What are its inputs and outputs at a *semantic* level — not just type?
- Which cross-cutting concerns does it participate in?
- What policies, alerts, dashboards, and runbooks does it ship?
- Which anti-patterns does it prevent? Which ADRs does it implement?
- Who owns it and what's its lifecycle status?

Today these questions require reading multiple files and inferring. The convention is well-trodden in adjacent spaces — Backstage's `catalog-info.yaml`, Helm's `Chart.yaml`, OpenAPI specs — but no existing artifact bridges *Terraform module + policy bundle + monitoring bundle + citation web + IDP catalog* in a single source of truth.

## Decision

Every module ships a **`manifest.yaml`** at its root. The manifest is the structured, machine-readable contract for the module. It is authoritative for the semantic metadata that HCL cannot express. HCL remains authoritative for the implementation. CI validates coherence between the two.

### Schema (top-level shape)

The full schema is in [`schemas/module-manifest.schema.json`](../../schemas/module-manifest.schema.json). The shape:

```yaml
apiVersion: vitruvius.io/v1
kind: Module
metadata:
  name: <module-name>
  area: <foundation|networking|platform-services|workload-patterns>
  version: <semver>
  status: <experimental|beta|stable|deprecated>
  owner: <team-alias>
  description: <one-line>
spec:
  inputs: []           # mirrors variables.tf, with semantic enrichment (vocabulary, semantic ties)
  outputs: []          # mirrors outputs.tf
  dependencies:
    avm: []             # AVM modules consumed (source + version)
    repo: []            # forbidden per ADR 0004 — must be empty
  cross_cutting:        # which cross-cutting concerns this module participates in
    identity: false
    observability: false
    secrets: false
    networking: false
    naming: false
    tagging: false
  ships:
    policy: []          # Azure Policy assignment names in policy/
    monitoring: []      # alert / workbook / dashboard names in monitoring/
    runbooks: []        # operational runbook references
  cites:
    principles: []      # firmitas | utilitas | venustas
    decisions: []       # ADR-XXXX
    anti_patterns: []   # AP-XXX
  examples: []          # name + description, mirrors examples/ subdirs
  tests: []             # name + type + description, mirrors tests/ files
```

### Validation in CI

CI (`scripts/validate-manifests.py`, run by the `manifest` job on every PR) enforces:

1. **Schema validation** against `schemas/module-manifest.schema.json`.
2. **Coherence checks** between manifest and code:
   - `metadata.name` and `metadata.area` match the module's directory path.
   - Declared `spec.inputs` match `variables.tf` — names in both directions, and `required` agrees with whether the variable has a default.
   - Declared `spec.outputs` match `outputs.tf` in both directions.
   - Declared `spec.dependencies.avm` sources and versions match `main.tf` module blocks.
   - `spec.dependencies.repo` is empty (enforces [ADR 0004](./0004-composition-by-output-data.md), also enforced by the schema itself).
   - Declared `spec.ships.policy` / `spec.ships.monitoring` entries resolve to a JSON file in `policy/`/`monitoring/` **or** to a resource defined in `main.tf` — alerts and initiatives are commonly inline Terraform (ADR 0003).
   - Declared `spec.examples` subdirs and `spec.tests` files exist — and, in reverse, everything on disk is declared.
   - Cited ADR IDs and AP IDs resolve to real ADR files / anti-pattern headings.
   - Every `policy/*.json` parses and carries the keys the modules' `jsondecode` calls rely on.
3. **Semantic-rule checks** (*planned, not yet wired*):
   - If `spec.cross_cutting.observability=true` and `spec.ships.monitoring` is empty, warn — a maturing module should ship monitoring, but an experimental module may not have alerts/dashboards defined yet (the schema treats this as a *should*, not an enforced invariant).
   - If `metadata.status=stable` but no consumer exists in `examples/` of another module, warn.
   - Module-area-specific rules can be added.

### Backstage integration

A converter generates `catalog-info.yaml` from `manifest.yaml`. Backstage TechDocs ingests `README.md` and `AGENTS.md` directly from this repo. There is no duplication; the manifest is the source of truth and Backstage views are derived. The converter lives in `scripts/` and is a normal repo artifact, not a separate service.

### Why one file, not several

The repo deliberately consolidates this metadata into one file rather than spreading it across `metadata.yaml`, `policy-bundle.yaml`, `monitoring-bundle.yaml`, `citations.yaml`. Reasons:

- One file to grep, one file to validate, one file for an AI agent to read first.
- The fields are coupled — changing inputs typically changes citations, ships, examples — and a single file makes that coupling visible in diffs.
- Splitting introduces a new mid-tier coupling shape, which [ADR 0004](./0004-composition-by-output-data.md) specifically prohibits at the module level.

### Why YAML, not HCL or JSON

- **HCL** would tempt module authors to compute manifest fields dynamically; the manifest must be static, declarative, and trivially parseable by any tool.
- **JSON** is harder to write by hand, lacks comments, and discourages the structured prose (descriptions) that auditors and humans read.
- **YAML** matches the convention of adjacent ecosystems (Backstage, Kubernetes, Helm) and is what most readers will already know.

## What this does not decide

- **The schema's future evolution** — `apiVersion: vitruvius.io/v1` is pinned; any breaking change is its own ADR with a migration plan.
- **When the `catalog-info.yaml` converter is actually wired** — this ADR specifies the Backstage bridge; *implementing* it is a separate work item, not yet live. (The manifest-validation CI step itself is live — see §Validation in CI; only the semantic-rule warnings remain unwired.)
- **The Backstage instance itself** — its deployment is gated behind the catalog-contract decision.

## Reversibility

**Load-bearing by design — cheap today, expensive later.** The manifest is meant to become the single contract that CI, the Backstage catalog, AI agents, and auditors all read. Today little consumes it, so changing its shape is still relatively cheap; every consumer that attaches (a CI validator, a catalog converter, an agent that expects fields) raises the cost of changing it. That asymmetry is the argument for getting the shape right *now*, while it is reversible — which is what this ADR does. The `apiVersion` pin keeps even future breaking changes a managed, migrate-forward path rather than a hard wall.

## Consequences

**Positive.**

- AI agents have a single structured entry point per module. The "where do I look first?" question has one answer.
- Backstage catalog and dependency graphs are derived, not maintained.
- Auditors get a structured view of "what controls does this module ship, citing which decisions?" via the manifest's `ships` and `cites` fields.
- Module conventions are *enforceable*, not aspirational. CI fails PRs that drift.
- Changes that affect cross-cutting concerns or compliance posture are visible in manifest diffs.

**Negative — and accepted.**

- The manifest duplicates input/output declarations from HCL. We accept this redundancy in exchange for a single AI-readable contract; CI catches drift, the trade is favorable.
- The schema will evolve. We pin `apiVersion: vitruvius.io/v1` and treat schema evolution as an ADR-level decision — any breaking change requires a new ADR and a migration plan.
- New modules must produce a manifest at creation. We accept this friction; the catalog and validation benefits are paid back at every consumer interaction.

## Cites

- [AP-009](../anti-patterns.md#ap-009--doc-rot) — manifest as a docs-with-code instance.
- [AP-012](../anti-patterns.md#ap-012--seagull-architecture) — structured manifests make module shape concretely reviewable by engineers, not opaque architect output.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — manifest enumerates what modules ship.
- [ADR 0004](./0004-composition-by-output-data.md) — manifest enforces no repo-internal cross-module dependencies.
