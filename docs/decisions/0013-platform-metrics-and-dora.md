---
id: 13
title: Platform health is measured; DORA is the starting frame
status: accepted
date: 2026-04-27
categories: [observability, change-management, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-007]
cites_adrs: [ADR-0005, ADR-0007, ADR-0010]
---

# ADR 0013 — Platform health is measured; DORA is the starting frame

## Context

A platform that is not measured cannot be improved, defended in budget conversations, or trusted by the teams it serves. "We feel like things are working" is [AP-007 — Change-management theater](../anti-patterns.md#ap-007--change-management-theater) inverted: heavyweight process exists, *and* nobody can answer "how is the platform actually performing?"

**DORA** — the DevOps Research and Assessment program, whose findings Forsgren, Humble, and Kim summarize in *Accelerate* — defined four metrics that are the industry-consensus starting point for measuring software-delivery performance. They are not the only metrics that matter, but they are the ones a platform team is expected to produce on demand.

This ADR captures the **discipline** — that we measure, and how. The **specific targets** are deliberately deferred to onboarding conversations with **stream-aligned teams** — the product teams that build features and consume the platform.

## Decision

### 1. The platform measures the four DORA metrics for every workload pattern

- **Deployment frequency** — how often code reaches production for a given service.
- **Lead time for changes** — how long a commit takes to reach production for a given service.
- **Change failure rate** — the fraction of deployments that degrade the service or require remediation.
- **Mean time to recovery (MTTR)** — how long it takes from detecting an incident to restoring the service.

The data flows through the **substrate** — the shared observability pipeline where all telemetry lands ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)). The deployment ledger from [ADR 0007](./0007-change-as-code.md) — the standing record of every deployment — is the source for the deployment-frequency and lead-time signals.

### 2. The platform reports a small set of platform-team-specific supplementary metrics

- **Time-to-first-deploy** — for a new app team onboarding to a workload pattern: the time from "I have an empty repo" to "my first commit reached production." This measures golden-path quality.
- **Self-service rate** — the fraction of platform-touching changes that complete without anyone on the platform team stepping in.

These are not industry standards, but they are load-bearing for the platform team's own posture. Time-to-first-deploy in particular is the leading indicator that the golden paths actually work.

### 3. Targets are not declared in this ADR

The discipline is the decision. The targets — what *good* looks like for deployment frequency, lead time, and so on — are set **with** the stream-aligned teams during workload-pattern onboarding, not declared by the platform team in advance.

This is deliberate. Targets declared without input from the consuming teams end up either aspirational (and ignored) or imposed (and resented). Targets set together with the teams are owned and defended.

### 4. The dashboard is part of the platform's product

Platform metrics live on a dashboard the consuming teams can see — the same data for everyone, no shadow scorecards. The dashboard's home is the substrate's visualization layer (an Azure Monitor workbook, Grafana, or whatever we land on per the deferred decisions below).

> **In plain terms:** the platform grades itself in public, and the teams it serves help write the grading rubric.

## What this does not decide

These items are explicitly **not** decided here. They are written down so they don't get lost; the process for resolving them is in §"How deferred decisions get made" below.

- **Tier-specific targets.** What "good" looks like for tier-0 vs tier-1 vs tier-2 vs tier-3 services (per the `business-criticality` tag taxonomy in [ADR 0010](./0010-tag-taxonomy.md)). Different criticality tiers carry different reasonable expectations.
- **Measurement infrastructure.** Whether the DORA metrics surface through Azure Monitor workbooks, a Grafana dashboard, a third-party DORA tool (LinearB, Sleuth, Faros, etc.), or some combination. The trade-off is build-vs-buy and how the data flows out of the substrate.
- **Cadence of review.** Weekly platform-team review? Monthly with stakeholders? Quarterly business review? Likely a layered cadence; the specifics are not yet decided.
- **Owner per metric.** The platform team owns the *plumbing*; the *targets* are co-owned with the stream-aligned teams. The exact accountability model still needs naming.
- **Time-to-first-deploy operationalization.** Easy to define, hard to measure cleanly. The instrumentation approach is open.

## How deferred decisions get made

- Targets are set per workload pattern during onboarding RFCs, not in this ADR.
- The measurement-infrastructure choice is a follow-up ADR with a real procurement / build-vs-buy comparison; it is not gated on this ADR.
- Review cadence and ownership get decided in the platform team's operating-model document, not in an ADR.
- This ADR is amended (via the `supersedes` / `superseded_by` chain) only if the *discipline* itself changes — for example, DORA gets supplemented with SPACE, or the supplementary-metrics list grows.

## Reversibility

**Cheap to change (two-way door).** The decision is "we measure, and DORA is the starting frame" — a measurement discipline, not infrastructure. Adding a metric family (SPACE, cost, security posture), swapping the dashboard tooling, or changing the review cadence are additive, low-blast-radius changes; the ADR already calls DORA the *starting* frame, not the whole frame. The one thing approaching a one-way commitment is cultural: once teams trust a shared scorecard, changing the definitions mid-stream erodes that trust — so metric *definitions* should change deliberately, even though they are mechanically easy to revise.

## Consequences

**Positive.**

- Platform health gets a vocabulary the team and its stakeholders share.
- The industry-standard framing answers "how do you measure platform success?" without inventing a bespoke scorecard.
- Time-to-first-deploy in particular forces honesty about whether the golden paths deliver on their promise.
- A dashboard treated as product reinforces the platform-as-product posture.

**Negative — and accepted.**

- DORA metrics on their own can be gamed (ship many trivial deploys to inflate frequency; suppress incident counts to flatter MTTR). The supplementary metrics and the qualitative review are the offsets; gaming the whole *suite* is harder.
- The four metrics don't cover everything. Cost, security posture, developer satisfaction, accessibility — all matter. Future ADRs may add metric families. We are explicit that DORA is the *starting* frame, not the *whole* frame.
- Measurement infrastructure has a real cost. We accept that observable platforms are not free.

## Cites

- [AP-007](../anti-patterns.md#ap-007--change-management-theater) — heavyweight process without measurement is the failure mode this ADR partially addresses.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — the substrate is where these metrics' data lives.
- [ADR 0007](./0007-change-as-code.md) — the deployment ledger feeds the deployment-frequency and lead-time signals.
- Forsgren, Humble, Kim — *Accelerate: The Science of Lean Software and DevOps* — the source of the four metrics.
