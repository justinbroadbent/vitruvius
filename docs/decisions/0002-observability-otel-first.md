---
id: 2
title: Observability is OpenTelemetry-first, emission target is configuration
status: accepted
date: 2026-04-26
categories: [observability]
supersedes: []
superseded_by: []
cites_anti_patterns: []
cites_adrs: []
---

# ADR 0002 — Observability is OpenTelemetry-first, emission target is configuration

## Context

The platform must support distributed tracing, metrics, and logs across a heterogeneous Azure estate. The team has not chosen a backend — Azure Monitor / Application Insights is the default Azure-native option; Datadog is under consideration; an OTLP-compatible alternative could become attractive.

If we hard-wire one backend into module SDKs and configuration, switching becomes a fleet-wide migration.

## Decision

All instrumentation in this repo emits **OpenTelemetry**.

Modules deploy or assume the presence of an **OpenTelemetry Collector** that fan-outs to one or more configured exporters. The exporter set is a per-environment input. Default: Azure Monitor exporter (Application Insights).

Service code (in workload-pattern examples) instruments via the **OpenTelemetry SDK** for its language, configured to point at the collector via OTLP. Code never imports Application Insights or Datadog SDKs directly.

## Consequences

**Positive:**

- Backend choice stays a deferrable, reversible decision.
- The same instrumentation works in dev (single-collector), prod (HA collector with multiple exporters), and during migration (dual-export to old and new backends).
- APM and trace capture are uniform across workloads regardless of language.

**Negative / things we accept:**

- Slightly more moving parts than "use Application Insights SDK directly" — we run the collector.
- Some Azure-native features (e.g., custom Application Insights queries) need to be expressed against whatever the collector exports. We accept this and treat it as a forcing function for portable observability.
- Datadog-specific UX (e.g., service catalog auto-detection) may require additional Datadog-side configuration beyond OTLP. We document the per-exporter caveats; we do not bend the collection format to suit any one backend.
