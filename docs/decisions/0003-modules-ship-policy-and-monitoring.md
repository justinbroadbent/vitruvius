---
id: 3
title: Modules ship their own policy and monitoring
status: accepted
date: 2026-04-26
categories: [foundation, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-001]
cites_adrs: []
---

# ADR 0003 — Modules ship their own policy and monitoring

## Context

The conventional shape in many estates is:

- A "platform" team owns infrastructure modules.
- A separate "monitoring" team adds dashboards, alerts, and diagnostic settings later.
- A separate "security" or "GRC" team adds Azure Policy assignments later.

This produces a long tail of resources without diagnostic settings, alerts that go stale because they're disconnected from the workloads they describe, and policy gaps that are only discovered in audit.

## Decision

**A module ships with the policy assignments and the monitoring artifacts that govern the resources it produces.** Concretely, every module's directory contains:

- `policy/` — Azure Policy assignments (or initiatives) targeting the module's outputs. If the module produces no auditable resources (e.g., a pure-logic naming module), the README states this explicitly.
- `monitoring/` — alert rules, workbook JSON, dashboard JSON. Diagnostic settings are wired in `main.tf` and emit to a Log Analytics workspace passed in as an input.

Operating expectations:

- A consumer who deploys a module gets the policy and monitoring **automatically**, without having to coordinate with another team.
- If a security or monitoring team wants to add controls beyond what the module ships, they do so via additional assignments at the management-group or subscription scope — not by editing module-level monitoring.

## Consequences

**Positive:**

- Net-new resources are observable and policy-governed from day one.
- Monitoring drift (alerts pointing at deleted resources; workbooks describing fields that no longer exist) drops to near-zero because monitoring is versioned with the resource.
- The module's contract is honest: "this is what I produce, and these are the controls and signals it carries."

**Negative / things we accept:**

- Module authors carry more responsibility — they cannot punt monitoring to a downstream team.
- Centralized monitoring teams need to adapt; their work shifts toward cross-cutting platforms (APM, log search, the OTel collector itself) rather than per-resource dashboarding.
- Some duplication is possible across modules with similar resources. We accept some duplication over the alternative — premature abstraction into a "shared monitoring" module that re-introduces the bolt-on shape.
