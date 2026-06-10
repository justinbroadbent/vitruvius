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

Every **module** in this repo — a reusable building block of infrastructure code — must ship its documentation, policy, monitoring, and tests alongside its **Terraform** code (Terraform is the tool that lets us describe cloud infrastructure as text files; the requirement comes from [ADR 0003](./0003-modules-ship-policy-and-monitoring.md)). Modules must connect to each other only through their declared outputs, never by reaching into each other's internals ([ADR 0004](./0004-composition-by-output-data.md)). And they cite, in prose docs, the anti-patterns they prevent and the principles they serve.

Right now that contract is scattered across many files in many formats: a prose `README.md`, a prose `AGENTS.md`, variable declarations in **HCL** (Terraform's configuration language), policy assignments in JSON, dashboard definitions in JSON, test files in HCL. Four kinds of readers — AI agents, the **Backstage** developer portal (an internal website cataloging every service, its owner, and its docs), auditors, and humans browsing the repo — all need answers to the same questions:

- What does this module do, at the level of abstraction it claims?
- What are its inputs and outputs at a *semantic* level — what they mean, not just what type they are?
- Which cross-cutting concerns (identity, networking, naming, and so on) does it participate in?
- What policies, alerts, dashboards, and runbooks does it ship?
- Which anti-patterns does it prevent? Which ADRs does it implement?
- Who owns it, and what is its lifecycle status?

Today, answering any of these means reading several files and inferring. The idea of a single descriptor file is well-trodden in neighboring ecosystems — Backstage's `catalog-info.yaml`, Helm's `Chart.yaml`, OpenAPI specs — but no existing format bridges *Terraform module + policy bundle + monitoring bundle + citation web + developer-portal catalog* in a single source of truth.

## Decision

Every module ships a **`manifest.yaml`** at its root: one structured, machine-readable file stating the module's contract. The manifest is authoritative for the meaning-level metadata that HCL cannot express; the HCL stays authoritative for the implementation itself. **CI** — the automated checks that run on every proposed change — validates that the two agree.

> **In plain terms:** the manifest is the module's ID card. The code says what the module *does*; the manifest says what it *is* — who owns it, what it promises, what it ships — in a format any tool can read in one pass.

### Schema (top-level shape)

The full schema lives in [`schemas/module-manifest.schema.json`](../../schemas/module-manifest.schema.json). The shape:

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

1. **Schema validation** — the manifest must match `schemas/module-manifest.schema.json`.
2. **Coherence checks** between the manifest and the code:
   - `metadata.name` and `metadata.area` match the module's directory path.
   - Declared `spec.inputs` match `variables.tf` — names checked in both directions, and `required` agrees with whether the variable has a default.
   - Declared `spec.outputs` match `outputs.tf` in both directions.
   - Declared `spec.dependencies.avm` sources and versions match the module blocks in `main.tf`.
   - `spec.dependencies.repo` is empty — modules may not depend on each other inside this repo (enforcing [ADR 0004](./0004-composition-by-output-data.md); the schema itself also enforces this).
   - Every declared `spec.ships.policy` / `spec.ships.monitoring` entry resolves to a JSON file in `policy/` / `monitoring/` **or** to a resource defined in `main.tf` — alerts and policy initiatives are often written inline in Terraform (ADR 0003).
   - Declared `spec.examples` subdirectories and `spec.tests` files exist — and, in reverse, everything on disk is declared.
   - Cited ADR IDs and AP IDs resolve to real ADR files / anti-pattern headings.
   - Every `policy/*.json` parses and carries the keys the modules' `jsondecode` calls rely on.
3. **Semantic-rule checks** (*planned, not yet wired*):
   - If `spec.cross_cutting.observability=true` but `spec.ships.monitoring` is empty, warn — a maturing module should ship monitoring, but an experimental module may not have alerts or dashboards defined yet (the schema treats this as a *should*, not an enforced invariant).
   - If `metadata.status=stable` but no other module's `examples/` consumes it, warn.
   - Module-area-specific rules can be added.

### Backstage integration

A converter generates Backstage's `catalog-info.yaml` from `manifest.yaml`. Backstage TechDocs — the portal's documentation viewer — reads `README.md` and `AGENTS.md` straight from this repo. Nothing is duplicated: the manifest is the source of truth, and the Backstage views are derived from it. The converter lives in `scripts/` and is an ordinary repo artifact, not a separate service.

### Why one file, not several

We deliberately put this metadata in one file rather than spreading it across `metadata.yaml`, `policy-bundle.yaml`, `monitoring-bundle.yaml`, and `citations.yaml`. Reasons:

- One file to search, one file to validate, one file for an AI agent to read first.
- The fields move together — changing inputs typically changes citations, ships, examples — and a single file makes that coupling visible in a diff.
- Splitting would introduce a new mid-tier coupling shape between files, exactly what [ADR 0004](./0004-composition-by-output-data.md) prohibits at the module level.

### Why YAML, not HCL or JSON

- **HCL** would tempt module authors to compute manifest fields dynamically. The manifest must be static, declarative, and trivially parseable by any tool.
- **JSON** is harder to write by hand, has no comments, and discourages the short prose descriptions that auditors and humans actually read.
- **YAML** is the convention in neighboring ecosystems (Backstage, Kubernetes, Helm), so it is the format most readers already know.

## What this does not decide

- **How the schema evolves.** `apiVersion: vitruvius.io/v1` is pinned; any breaking change gets its own ADR with a migration plan.
- **When the `catalog-info.yaml` converter is actually wired up.** This ADR specifies the Backstage bridge; *building* it is a separate work item, not yet live. (The manifest-validation CI step itself *is* live — see §Validation in CI; only the semantic-rule warnings remain unwired.)
- **The Backstage instance itself.** Deploying the portal is gated behind the catalog-contract decision.

## Reversibility

**Load-bearing by design — cheap today, expensive later.** The manifest is meant to become the single contract that CI, the Backstage catalog, AI agents, and auditors all read. Today little consumes it, so changing its shape is still relatively cheap. But every consumer that attaches — a CI validator, a catalog converter, an agent that expects certain fields — raises the cost of changing it. That asymmetry is the argument for getting the shape right *now*, while it is still reversible — which is what this ADR does. The pinned `apiVersion` keeps even a future breaking change a managed, migrate-forward path rather than a hard wall.

## Consequences

**Positive.**

- AI agents get a single structured entry point per module. "Where do I look first?" has one answer.
- The Backstage catalog and dependency graphs are generated, not hand-maintained.
- Auditors get a structured answer to "what controls does this module ship, citing which decisions?" through the manifest's `ships` and `cites` fields.
- Module conventions become *enforceable*, not aspirational. CI fails any PR where manifest and code drift apart.
- Changes that affect cross-cutting concerns or compliance posture show up plainly in manifest diffs.

**Negative — and accepted.**

- The manifest repeats the input/output declarations already in HCL. We accept the redundancy in exchange for a single AI-readable contract; CI catches drift, so the trade is favorable.
- The schema will evolve. We pin `apiVersion: vitruvius.io/v1` and treat schema evolution as an ADR-level decision — any breaking change requires a new ADR and a migration plan.
- Every new module must ship a manifest from day one. We accept the friction; the catalog and validation benefits pay it back at every consumer interaction.

## Cites

- [AP-009](../anti-patterns.md#ap-009--doc-rot) — the manifest is an instance of docs living with the code.
- [AP-012](../anti-patterns.md#ap-012--seagull-architecture) — structured manifests make a module's shape concretely reviewable by engineers, not opaque architect output.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — the manifest enumerates what each module ships.
- [ADR 0004](./0004-composition-by-output-data.md) — the manifest enforces "no repo-internal cross-module dependencies."
