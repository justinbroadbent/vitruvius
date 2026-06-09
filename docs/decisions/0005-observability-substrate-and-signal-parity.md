---
id: 5
title: Centralized observability substrate with federated curation; signal parity across environments
status: accepted
date: 2026-04-26
categories: [observability]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-001, AP-002, AP-011]
cites_adrs: [ADR-0002, ADR-0003, ADR-0013]
---

# ADR 0005 — Centralized observability substrate with federated curation; signal parity across environments

## Context

Three well-attested failure modes pull observability in different directions:

- [AP-001 — Bolted-on monitoring](../anti-patterns.md#ap-001--bolted-on-monitoring) — separate teams own the monitoring, so the dashboards and alerts drift away from the resources they describe.
- [AP-002 — Telemetry dumping ground](../anti-patterns.md#ap-002--telemetry-dumping-ground) — a centralized backend with no curation becomes an expensive swamp nobody can search.
- [AP-011 — Lower-env signal gap](../anti-patterns.md#ap-011--lower-env-signal-gap) — production is heavily monitored, the lower environments (dev and staging) barely are, so regressions surface only in production.

A healthy observability story has to navigate all three at once. Decentralizing solves the dumping ground but reintroduces fragmentation. Centralizing solves fragmentation but creates the dumping ground. Cutting lower-environment telemetry saves money but moves regression detection into production.

[ADR 0002](./0002-observability-otel-first.md) committed to OpenTelemetry as the collection format. This ADR specifies the **substrate** — the shared plumbing and storage that receives all that telemetry — and the operational rules that govern it.

## Decision

The observability story has three coupled rules.

**1. Centralized substrate, federated curation.** One shared place, with the upkeep rules below binding everyone who emits into it. A single OpenTelemetry Collector deployment per environment fans out to one or more configured exporters (Azure Monitor / Application Insights by default; Datadog optionally; any OTLP-compatible alternative pluggable). Services emit OTLP to the collector and never talk to a backend SDK directly.

**2. Opinionated semantic conventions enforced at ingest.** **Semantic conventions** are standard names and labels for telemetry; "enforced at ingest" means the collector checks them as the data arrives.

- **Required attributes** per signal — at minimum, `service.name`, `service.version`, `deployment.environment`, `cloud.region`, `telemetry.sdk.*`. The collector drops or quarantines signals that don't conform.
- **Cardinality budgets per service.** **Cardinality** is the number of distinct label combinations a service emits — the thing that quietly blows up monitoring bills. The collector enforces a maximum tag cardinality and metric series count per service. Exceeding the budget alerts the service owner.
- **Retention tiers** — how long data is kept, and where. Hot (Log Analytics, 30 days) for active troubleshooting. Warm (Log Analytics archive or Datadog cold, 1 year) for trend analysis. Cold (Blob Storage with Parquet files, 7 years) for audit retention. Most of the cost wins live in this tiering.
- **Dashboard ownership.** Every dashboard has an `owner` tag matching a team alias. A quarterly sunset job warns about, then removes, dashboards with no recent views and no owner response.

**3. Signal parity across environments.** Dev, staging, and prod carry identical OTel instrumentation. Retention differs (dev: 7 days; staging: 14 days; prod: per the tiers above); the *signal set* does not. Performance budgets in CI block deploys that regress p99 latency (the response time of the slowest 1% of requests), error rate, or throughput beyond a per-service threshold. The rule: if it is not monitored in staging, it does not deploy to production.

Modules still ship the diagnostic settings and alerts that govern their own resources (per [ADR 0003](./0003-modules-ship-policy-and-monitoring.md)). The substrate itself (the Log Analytics workspace plus Application Insights) is deployed by `modules/platform-services/observability-substrate`; the collector deployment depends on the host and is separate.

## What this does not decide

- **The concrete knob values** — the retention windows (30d/1y/7y), cardinality budgets, and per-environment retention (dev 7d / staging 14d / prod tiered) are reference defaults, not fixed law; an adopter tunes them.
- **The exporter set and substrate topology** — backend choice (inherited from ADR 0002) and the collector's HA/region shape are environment configuration.
- **The visualization/dashboard tooling** — Azure Monitor workbooks vs Grafana vs other is deferred (see ADR 0013).

## Reversibility

- **The structural rules — centralized substrate, semantic conventions, signal parity — are load-bearing (a one-way door).** Once services emit into a single substrate, and tooling, dashboards, and CI performance budgets all assume conformant signals and cross-environment parity, unwinding any of it is an estate-wide change, not a config flip.
- **The numeric knobs (retention, cardinality budgets) are cheap to change (a two-way door)** — they are policy settings on the collector, tunable per environment with low blast radius.
- **The backend is two-way** by construction (ADR 0002). Signal parity is the subtle one: cheap to *state*, expensive to *claw back* once lower-environment tooling depends on it — so commit to it deliberately.

> **In plain terms:** one well-run library instead of either a hoarder's garage or a hundred private bookshelves — and the rehearsal stage gets the same instruments as opening night, so problems get found in rehearsal.

## Consequences

**Positive.**

- Cost is controlled up front, because cardinality and retention are budgeted rather than discovered on the bill.
- Backend choice (App Insights vs. Datadog vs. an OTLP-compatible alternative) is configuration; switching does not require service-code changes.
- Regressions are detected pre-merge and pre-promote, not post-deploy.
- Audit-grade signals (the cold tier) are retained without inflating the hot backend's cost.
- New services emit complete telemetry from day one — no waiting on a monitoring team's backlog.

**Negative — and accepted.**

- The collector is infrastructure the platform team operates. We accept this in exchange for reversibility on backend choice and a uniform signal shape.
- Cardinality budgets occasionally reject signals teams want to emit. The budget is reviewable; the answer is to make the case for the cardinality, not to bypass the budget.
- Backend-specific conveniences (e.g., Datadog Service Catalog auto-detection, App Insights smart-detection) require per-exporter configuration that is not portable across backends. We document the per-exporter caveats and accept that some features are tied to a specific backend.
- Lower-environment retention is short, so historical analysis of dev incidents is limited. We treat lower-env data as troubleshooting telemetry, not a historical record.

## Cites

- [AP-001](../anti-patterns.md#ap-001--bolted-on-monitoring) — addressed by modules-ship-monitoring plus the collector substrate.
- [AP-002](../anti-patterns.md#ap-002--telemetry-dumping-ground) — addressed by semantic conventions, cardinality budgets, retention tiers, and dashboard ownership.
- [AP-011](../anti-patterns.md#ap-011--lower-env-signal-gap) — addressed by the signal-parity rule and CI performance budgets.
- [ADR 0002](./0002-observability-otel-first.md) — extended here into the substrate's shape.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — modules-ship-monitoring is unchanged; this ADR adds the substrate they emit into.
