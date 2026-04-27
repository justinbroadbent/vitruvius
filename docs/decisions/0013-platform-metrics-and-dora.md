---
id: 13
title: Platform health is measured; DORA is the starting frame
status: accepted
date: 2026-04-27
categories: [observability, change-management, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-007]
cites_adrs: [ADR-0005, ADR-0007]
---

# ADR 0013 — Platform health is measured; DORA is the starting frame

## Context

A platform that is not measured cannot be improved, defended in budget conversations, or trusted by the teams it serves. "We feel like things are working" is the failure mode in [AP-007 — ITIL ceremony](../anti-patterns.md#ap-007--itil-ceremony) inverted: heavyweight process exists *and* nobody can answer "how is the platform actually performing?"

DORA's four metrics (Forsgren / Humble / Kim, *Accelerate*) are the industry-consensus starting point for measuring software-delivery performance. They are not the only metrics that matter, but they are the ones a platform team is expected to be able to produce on demand.

This ADR captures the **discipline** — that we measure, and how. The **specific targets** are deliberately deferred to onboarding conversations with stream-aligned teams.

## Decision

### 1. The platform measures the four DORA metrics for every workload pattern

- **Deployment frequency** — how often code reaches production for a given service.
- **Lead time for changes** — time from commit to production for a given service.
- **Change failure rate** — fraction of deployments that cause a degraded service / require remediation.
- **Mean time to recovery (MTTR)** — time from incident detection to service restored.

Data flows through the substrate ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)). The deployment-ledger from [ADR 0007](./0007-change-as-code.md) is the source for deployment-frequency and lead-time signals.

### 2. The platform reports a small set of platform-team-specific supplementary metrics

- **Time-to-first-deploy** — for a new app team onboarding to a workload pattern, time from "I have an empty repo" to "my first commit reached production." Measures golden-path quality.
- **Self-service rate** — fraction of platform-touching changes that complete without platform-team intervention.

These are not industry-standard, but they are load-bearing for the platform-team's own posture. Time-to-first-deploy in particular is the leading indicator that the golden paths actually work.

### 3. Targets are not declared in this ADR

The discipline is the decision. The targets — what *good* looks like for deployment frequency, lead time, etc. — are decisions made **with** the stream-aligned teams during workload-pattern onboarding, not declared by the platform team in advance.

This is deliberate. Targets declared without the consuming teams' input are either aspirational (and ignored) or imposed (and resented). Targets declared with the teams are owned and defended.

### 4. The dashboard is part of the platform's product

Platform metrics are surfaced in a dashboard the consuming teams can see — same data, no shadow scorecards. The dashboard's home is the substrate's visualization layer (Azure Monitor workbook, Grafana, or whatever we land on per the deferred decisions below).

## Decisions deferred

These are explicitly **not** decided here. They are captured so they don't get lost; the process for resolving them is in §"How deferred decisions get made" below.

- **Tier-specific targets.** What "good" looks like for tier-0 vs tier-1 vs tier-2 vs tier-3 services (per the `business-criticality` tag taxonomy in [ADR 0010](./0010-tag-taxonomy.md)). Different tiers have different reasonable expectations.
- **Measurement infrastructure.** Whether DORA metrics surface via Azure Monitor workbooks, a Grafana dashboard, a third-party DORA tool (LinearB, Sleuth, Faros, etc.), or some combination. Trade-off is build-vs-buy and how the data flows from the substrate.
- **Cadence of review.** Weekly platform-team review? Monthly with stakeholders? Quarterly business review? Likely a layered cadence; specifics not yet decided.
- **Owner per metric.** The platform team owns the *plumbing*; the *targets* are co-owned with stream-aligned teams. The exact accountability model needs naming.
- **Time-to-first-deploy operationalization.** Easy to define, hard to measure cleanly. The instrumentation approach is open.

## How deferred decisions get made

- Targets are set per-workload-pattern during onboarding RFCs, not in this ADR.
- Measurement-infrastructure choice is a follow-up ADR with a real procurement / build-vs-buy comparison; not gated on this ADR.
- Cadence of review and ownership get decided in the platform-team operating-model document, not in an ADR.
- This ADR is amended (`supersedes` / `superseded_by` chain) if the *discipline* itself changes — e.g., DORA gets supplemented with SPACE, or the supplementary metrics list grows.

## Consequences

**Positive.**

- Platform health has a vocabulary the team and stakeholders share.
- Industry-standard framing answers "how do you measure platform success?" without inventing a bespoke scorecard.
- Time-to-first-deploy in particular forces honesty about whether the golden paths actually deliver on their promise.
- Dashboards-as-product reinforces the platform-as-product posture.

**Negative — and accepted.**

- DORA metrics on their own can be gamed (ship many trivial deploys to inflate frequency; suppress incident counts to flatter MTTR). The supplementary metrics and the qualitative review are the offsets; gaming the *suite* is harder.
- The four metrics don't cover everything. Cost, security posture, developer satisfaction, accessibility — all matter. Future ADRs may add metric families. We are explicit that DORA is the *starting* frame, not the *whole* frame.
- Measurement infrastructure has a real cost. We accept that observable platforms are not free.

## Cites

- [AP-007](../anti-patterns.md#ap-007--itil-ceremony) — heavyweight process without measurement is the failure mode this ADR partially addresses.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — the substrate is where these metrics' data lives.
- [ADR 0007](./0007-change-as-code.md) — the deployment ledger feeds deployment-frequency and lead-time signals.
- Forsgren, Humble, Kim — *Accelerate: The Science of Lean Software and DevOps* — the source of the four metrics.
