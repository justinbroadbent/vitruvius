---
id: 2
title: Observability is OpenTelemetry-first, emission target is configuration
status: accepted
date: 2026-04-26
categories: [observability]
supersedes: []
superseded_by: []
cites_anti_patterns: []
cites_adrs: [ADR-0005]
---

# ADR 0002 — Observability is OpenTelemetry-first, emission target is configuration

## Context

The platform must support **observability** — the ability to see what running systems are doing — through three kinds of telemetry: **traces** (the path one request takes through many services), **metrics** (numbers over time), and **logs** (text records of events), across a varied Azure estate. The team has not chosen a **backend** — the product that stores and displays all this data. Azure Monitor / Application Insights is the default Azure-native option; Datadog is under consideration; an alternative that speaks **OTLP** (the OpenTelemetry wire protocol) could become attractive later.

If we wire one backend directly into module SDKs and configuration, switching later becomes a fleet-wide migration — every service gets touched.

## Decision

All instrumentation in this repo emits **OpenTelemetry** (OTel) — the open, vendor-neutral standard format for telemetry.

Modules deploy, or assume the presence of, an **OpenTelemetry Collector** — a middleman service that receives all telemetry and fans it out to one or more configured **exporters** (the connectors to actual backends). The exporter set is a per-environment input. Default: the Azure Monitor exporter (Application Insights).

Service code (in workload-pattern examples) instruments via the **OpenTelemetry SDK** for its language, pointed at the collector over OTLP. Code never imports the Application Insights or Datadog SDKs directly.

## What this does not decide

- **The backend / exporter set** — Azure Monitor vs Datadog vs any OTLP-compatible alternative is a per-environment input, not decided here. Deferring that choice is the whole point of this ADR.
- **The collector deployment topology** — a single collector vs a highly available (HA) fan-out is an environment and platform-services concern (ADR 0005).
- **Which language SDKs** — each workload instruments in its own language; the platform fixes the *format*, not the runtime.

## Reversibility

The two halves of this decision sit deliberately on opposite sides of the door:

- **OpenTelemetry as the collection format: load-bearing (a one-way door).** Every instrumented service emits OTel; abandoning it would mean re-instrumenting the whole estate. This is the commitment the ADR is making.
- **The emission target: cheap to change (a two-way door).** Backend choice is configuration on the collector — switching, or exporting to old and new backends at once during a migration, requires no change to service code. The collector middleman is exactly the optionality that keeps backend choice reversible.

> **In plain terms:** it works like a universal power adapter. Every service plugs into the collector the same way, and the collector handles whatever the wall socket (the backend vendor) happens to be. Change vendors, and only the socket side changes.

## Consequences

**Positive:**

- Backend choice stays a deferrable, reversible decision.
- The same instrumentation works in dev (single collector), prod (HA collector with multiple exporters), and during migration (dual-export to old and new backends).
- Application performance monitoring (APM) and trace capture look the same across workloads regardless of language.

**Negative / things we accept:**

- Slightly more moving parts than "use the Application Insights SDK directly" — we run the collector.
- Some Azure-native features (e.g., custom Application Insights queries) must be expressed against whatever the collector exports. We accept this and treat it as a forcing function for portable observability.
- Datadog-specific conveniences (e.g., its service-catalog auto-detection) may require extra Datadog-side configuration beyond OTLP. We document the per-exporter caveats; we do not bend the collection format to suit any one backend.
