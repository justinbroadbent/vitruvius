---
id: 5
title: Centralized observability substrate with federated curation; signal parity across environments
status: accepted
date: 2026-04-26
categories: [observability]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-001, AP-002, AP-011]
cites_adrs: [ADR-0002, ADR-0003]
---

# ADR 0005 — Centralized observability substrate with federated curation; signal parity across environments

## Context

Three failure modes around observability are well-attested in practice:

- [AP-001 — Bolted-on monitoring](../anti-patterns.md#ap-001--bolted-on-monitoring) — separate teams own monitoring; artifacts drift from the resources they describe.
- [AP-002 — Telemetry dumping ground](../anti-patterns.md#ap-002--telemetry-dumping-ground) — centralized backend becomes uncurated cost center.
- [AP-011 — Lower-env signal gap](../anti-patterns.md#ap-011--lower-env-signal-gap) — production is heavily monitored, lower envs aren't, regressions surface in production.

A healthy observability story has to navigate all three. Decentralizing solves the dumping ground but reintroduces fragmentation. Centralizing solves fragmentation but creates the dumping ground. Cutting lower-env telemetry saves cost but moves regression detection to production.

[ADR 0002](./0002-observability-otel-first.md) committed to OpenTelemetry as the collection format. This ADR specifies the substrate that consumes OTLP and the operational rules that govern it.

## Decision

The observability story has three coupled rules.

**1. Centralized substrate, federated curation.** A single OpenTelemetry Collector deployment per environment fans out to one or more configured exporters (Azure Monitor / Application Insights by default; Datadog optionally; any OTLP-compatible alternative pluggable). Services emit OTLP to the collector and never directly to a backend SDK.

**2. Opinionated semantic conventions enforced at ingest.**

- **Required attributes** per signal — at minimum, `service.name`, `service.version`, `deployment.environment`, `cloud.region`, `telemetry.sdk.*`. The collector drops or quarantines non-conformant signals.
- **Cardinality budgets per service.** The collector enforces a maximum tag cardinality and metric series count per service. Exceeding the budget alerts the service owner.
- **Retention tiers.** Hot (Log Analytics, 30 days) for active troubleshooting. Warm (Log Analytics archive or Datadog cold, 1 year) for trend analysis. Cold (Blob Storage with Parquet, 7 years) for audit retention. Most cost wins live in retention tiering.
- **Dashboard ownership.** Every dashboard has an `owner` tag matching a team alias. Quarterly sunset job warns and removes dashboards with no recent views and no owner response.

**3. Signal parity across environments.** Identical OTel instrumentation in dev, staging, and prod. Retention differs (dev: 7d; staging: 14d; prod: per tier above); the *signal set* does not. Performance budgets in CI block deploys that regress p99 latency, error rate, or throughput beyond a per-service threshold. The rule: if it is not monitored in staging, it does not deploy to production.

Modules ship the diagnostic settings and alerts that govern their resources (per [ADR 0003](./0003-modules-ship-policy-and-monitoring.md)). The collector and substrate are deployed by `modules/platform-services/observability`.

## What this does not decide

- **The concrete knob values** — the retention windows (30d/1y/7y), cardinality budgets, and per-environment retention (dev 7d / staging 14d / prod tiered) are stated as reference defaults, not fixed law; an adopter tunes them.
- **The exporter set and substrate topology** — backend choice (inherited from ADR 0002) and the collector's HA/region shape are environment configuration.
- **The visualization/dashboard tooling** — Azure Monitor workbooks vs Grafana vs other is deferred (see ADR 0013).

## Reversibility

- **The structural rules — centralized substrate, semantic conventions, signal parity — are load-bearing (one-way door).** Once services emit into a single substrate and tooling, dashboards, and CI performance-budgets assume conformant signals and cross-environment parity, unwinding them is an estate-wide change, not a config flip.
- **The numeric knobs (retention, cardinality budgets) are cheap to change (two-way door)** — they are policy on the collector, tunable per environment with low blast radius.
- **The backend is two-way** by construction (ADR 0002). Signal parity is the subtle one: cheap to *state*, expensive to *claw back* once lower-env tooling depends on it — so commit to it deliberately.

## Consequences

**Positive.**

- Cost is controlled because cardinality and retention are budgeted, not discovered after the fact.
- Backend choice (App Insights vs. Datadog vs. OTLP-compatible alternative) is configuration; switching does not require service-code changes.
- Regressions are detected pre-merge and pre-promote, not post-deploy.
- Audit-grade signals (cold tier) are retained without inflating the hot backend cost.
- New services emit complete telemetry from day one — no waiting on a monitoring team backlog.

**Negative — and accepted.**

- The collector is infrastructure the platform team operates. We accept this in exchange for reversibility on backend choice and uniform signal shape.
- Cardinality budgets occasionally reject signals teams want to emit. The budget is reviewable; the answer is to make the case for the cardinality, not to bypass the budget.
- Backend-specific UX (e.g., Datadog Service Catalog auto-detection, App Insights smart-detection) requires per-exporter configuration that is not portable across backends. We document the per-exporter caveats and accept that some features are tied to a specific backend.
- Lower-env retention is short, so historical analysis of dev incidents is limited. We treat lower-env data as troubleshooting telemetry, not historical record.

## Cites

- [AP-001](../anti-patterns.md#ap-001--bolted-on-monitoring) — modules-ship-monitoring + collector substrate.
- [AP-002](../anti-patterns.md#ap-002--telemetry-dumping-ground) — semantic conventions, cardinality budgets, retention tiers, dashboard ownership.
- [AP-011](../anti-patterns.md#ap-011--lower-env-signal-gap) — signal parity rule and CI performance budgets.
- [ADR 0002](./0002-observability-otel-first.md) — extended into substrate shape.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — modules-ship-monitoring is unchanged; this ADR adds the substrate they emit into.
