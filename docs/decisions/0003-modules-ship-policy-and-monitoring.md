---
id: 3
title: Modules ship their own policy and monitoring
status: accepted
date: 2026-04-26
categories: [foundation, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-001]
cites_adrs: [ADR-0005, ADR-0011]
---

# ADR 0003 — Modules ship their own policy and monitoring

## Context

The conventional arrangement in many organizations splits one job across three teams:

- A "platform" team builds the infrastructure modules.
- A separate "monitoring" team adds the dashboards, alerts, and diagnostic settings later.
- A separate "security" or "GRC" (governance, risk, and compliance) team adds the **Azure Policy** assignments — Azure's automated governance rules — later.

Every handoff is a seam that drifts. The result: a long tail of resources with no diagnostic settings, alerts that go stale because they are disconnected from the workloads they describe, and policy gaps discovered only at audit time.

## Decision

**A module ships with the policy assignments and the monitoring artifacts that govern the resources it produces.** The rules and the dashboards travel in the same package as the thing they watch. Concretely:

- **Policy** — Azure Policy definitions ship as JSON in the module's `policy/` folder; the **initiative** (a named bundle of related policies) and the assignment that activate them are Terraform resources in `main.tf`. If the module produces no auditable resources (e.g., a pure-logic naming module), the README states this explicitly.
- **Monitoring** — alert rules may be defined inline in `main.tf` as Terraform resources (the common case for a handful of alerts); workbook and dashboard JSON live in `monitoring/`. **Diagnostic settings** — the switch that makes an Azure resource emit its logs and metrics — are wired in `main.tf` and emit to a Log Analytics workspace passed in as an input.
- Either way, the module's `manifest.yaml` (its machine-readable spec sheet) names everything it ships in `spec.ships`, and CI checks that each name resolves to a file in `policy/`/`monitoring/` or to a resource defined in `main.tf` (ADR 0011).
- An experimental module may ship no monitoring yet — but its README must say so explicitly rather than leaving the gap implied.

Operating expectations:

- A consumer who deploys a module gets the policy and monitoring **automatically**, without having to coordinate with another team.
- If a security or monitoring team wants controls beyond what the module ships, they add assignments at the **management-group** or subscription scope (a management group is a folder that groups Azure subscriptions so one rule can govern many of them) — they do not edit module-level monitoring.

## What this does not decide

- **Where org-wide controls beyond the module are assigned** — management-group / subscription-scope assignments are the consumer's (landing-zone's) call, not the module's.
- **The specific alert thresholds, workbooks, and dashboards** each module ships — that is per-module authoring, sized to the resources the module produces.
- **The monitoring backend** the artifacts emit into — that is the observability substrate (ADR 0005).

## Reversibility

**Load-bearing (a one-way door) as a convention.** This decision shapes every module's directory layout and the authoring contract: an author owns the policy and monitoring, not just the resources. The artifacts themselves are additive and per-module — but reversing the *convention*, by re-homing policy and monitoring into separate bolt-on teams, means redistributing artifacts across every module and re-opening [AP-001](../anti-patterns.md#ap-001--bolted-on-monitoring), the bolted-on-monitoring trap. What would have to change is not any single module mechanically, but the team topology and the review expectation. The convention is cheap to erode one module at a time and expensive to recover estate-wide — hence it is enforced by review and by the manifest's `ships` contract (ADR 0011).

> **In plain terms:** a car comes with its dashboard and warning lights built in. You don't buy the car and then hire a separate company to bolt on a speedometer that may or may not match the engine.

## Consequences

**Positive:**

- Net-new resources are observable and policy-governed from day one.
- Monitoring drift — alerts pointing at deleted resources, workbooks describing fields that no longer exist — drops to near zero, because the monitoring is versioned together with the resource it watches.
- The module's contract is honest: "this is what I produce, and these are the controls and signals it carries."

**Negative / things we accept:**

- Module authors carry more responsibility — they cannot hand monitoring off to a downstream team.
- Centralized monitoring teams need to adapt; their work shifts toward cross-cutting platforms (APM, log search, the OTel collector itself) rather than per-resource dashboarding.
- Some duplication is possible across modules with similar resources. We accept some duplication over the alternative — prematurely extracting a "shared monitoring" module, which would re-introduce the bolt-on shape this ADR exists to prevent.
