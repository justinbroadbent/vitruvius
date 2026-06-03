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

## What this does not decide

- **Where org-wide controls beyond the module are assigned** — management-group / subscription-scope assignments are the consumer's (landing-zone's) call, not the module's.
- **The specific alert thresholds, workbooks, and dashboards** each module ships — that is per-module authoring, sized to the resources it produces.
- **The monitoring backend** the artifacts emit into — that is the observability substrate (ADR 0005).

## Reversibility

**Load-bearing (one-way door) as a convention.** This decision shapes every module's directory layout and the authoring contract (an author owns policy + monitoring, not just resources). The artifacts themselves are additive and per-module, but reversing the *convention* — re-homing policy and monitoring into separate bolt-on teams — means re-distributing artifacts across every module and re-opening [AP-001](../anti-patterns.md#ap-001--bolted-on-monitoring). What would have to change: not a single module mechanically, but the team topology and the review expectation. Cheap to erode one module at a time, expensive to recover estate-wide — hence enforced by review and the manifest's `ships` contract (ADR 0011).

## Consequences

**Positive:**

- Net-new resources are observable and policy-governed from day one.
- Monitoring drift (alerts pointing at deleted resources; workbooks describing fields that no longer exist) drops to near-zero because monitoring is versioned with the resource.
- The module's contract is honest: "this is what I produce, and these are the controls and signals it carries."

**Negative / things we accept:**

- Module authors carry more responsibility — they cannot punt monitoring to a downstream team.
- Centralized monitoring teams need to adapt; their work shifts toward cross-cutting platforms (APM, log search, the OTel collector itself) rather than per-resource dashboarding.
- Some duplication is possible across modules with similar resources. We accept some duplication over the alternative — premature abstraction into a "shared monitoring" module that re-introduces the bolt-on shape.
