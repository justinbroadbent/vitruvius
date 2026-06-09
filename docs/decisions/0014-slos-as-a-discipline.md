---
id: 14
title: SLOs are a per-workload discipline; the platform provides the framework, not the targets
status: accepted
date: 2026-04-27
categories: [observability, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-002]
cites_adrs: [ADR-0005, ADR-0011, ADR-0013]
---

# ADR 0014 — SLOs are a per-workload discipline; the platform provides the framework, not the targets

## Context

**Service Level Objectives (SLOs)** — a practice from the Google SRE Book — turn "the service is fine" into a measurable, defensible claim. An SLO is a reliability target a team commits to (say, "99.9% of requests succeed"); the gap between that target and perfection is the **error budget** — the amount of failure the team is allowed before it must act. Without SLOs, an incident is "the service felt slow." With them, it is "we burned 17% of the latency error budget for this quarter, and here is what we are doing about it." The substrate from [ADR 0005](./0005-observability-substrate-and-signal-parity.md) collects the data; the SLO discipline is what *uses* the data to make decisions.

The risk if we skip this discipline: the substrate becomes a [telemetry dumping ground (AP-002)](../anti-patterns.md#ap-002--telemetry-dumping-ground) — every signal collected, no signal acted upon.

This ADR captures the **discipline** — that workloads have SLOs, and how the platform supports them. The **specific targets per workload** are explicitly the workload team's decision, not the platform team's.

## Decision

### 1. Every production workload declares SLOs

Workload-pattern modules (e.g., `web-api-aks`) will eventually expose an `slo` declaration in their manifest. v0.1.0 manifests do not yet require this — the schema field is deferred until the per-workload structure is decided (see §"Decisions deferred"). When the field arrives, every production-tier workload is expected to populate it; lower tiers are encouraged but not required.

Suggested initial dimensions (workload teams choose what applies):

- **Availability** — the fraction of well-formed requests that succeed.
- **Latency** — the fraction of well-formed requests served within a stated time bound.
- **Freshness** (for data pipelines) — how stale the data is by the time the consumer reads it.
- **Correctness** (where measurable) — the fraction of operations that produce the expected outcome.

### 2. The platform provides the framework, not the numbers

The platform team owns:

- The substrate that emits the metrics.
- The **SLI** definitions for each workload pattern — an SLI ("service level indicator") is the measurement itself, including what counts as a "well-formed request."
- The dashboard and alerting plumbing.
- The error-budget *concept* and the **burn-rate** alerting *mechanism* — burn rate being how fast a workload is consuming its error budget.

The workload team owns:

- The numeric targets for each SLO.
- The error-budget policy: what happens when the budget is consumed, who decides feature freezes, and how the budget interacts with planned work.
- The review cadence with stakeholders.

This split is deliberate: the platform team has no business deciding 99.9% versus 99.95% for a service it does not operate.

> **In plain terms:** the platform supplies the measuring tape and the alarm bell; each team decides where to draw its own line — because the team that operates a service is the only one that can honestly promise how reliable it will be.

### 3. Error budgets are a real lever, not theater

When a workload exhausts its error budget, that workload's own policy applies. Common options (each workload picks):

- Freeze feature work until the budget recovers.
- Escalate to the platform team for a substrate-level investigation.
- Renegotiate the SLO target with stakeholders (and document the renegotiation).

What is **not** acceptable: silently consuming the budget month after month with no consequence. That turns the SLO into theater.

### 4. SLOs are workload-level by default; platform-level SLOs exist where they make sense

Some platform components — the substrate itself, the policy-evaluation pipeline, **APIM** (Azure API Management, the shared API gateway) — have SLOs of their own, because they are services the workload teams consume. Those SLOs *are* the platform team's to set, because the platform team operates them.

This is the symmetric case: anyone who runs a service declares SLOs for it. The platform team runs services too.

## What this does not decide

- **Manifest-schema shape.** What `slo:` looks like inside `manifest.yaml`. The structure has to support multiple SLI dimensions, target values, measurement windows, and possibly burn-rate alerting thresholds. Deferred until at least one workload team has a real SLO to declare; the schema follows reality, not the other way around.
- **Default target percentiles per business-criticality tier.** Tier-0 should clearly carry stricter SLOs than tier-3, but the specific numbers (99.95% vs 99.9% vs 99.5%) are workload-team decisions made in collaboration with stakeholders.
- **Error-budget policy templates.** Whether the platform team provides 2–3 named templates (e.g., "feature-freeze on budget exhaustion," "escalation-only on budget exhaustion") that workloads can adopt, or whether each workload writes its own. The trade-off is conformity vs autonomy.
- **Alerting strategy.** Multi-window, multi-burn-rate alerting (Google SRE workbook, chapter 5) is the established best practice, but the specific window/burn-rate matrix is per-workload.
- **Tooling.** Whether SLOs are computed in Azure Monitor workbooks, a third-party SLO platform (Nobl9, Datadog SLOs, etc.), or open source (Pyrra, Sloth). Build-vs-buy not yet decided.
- **Where SLO data lives in the substrate.** Likely a separate Log Analytics table or workspace, but the architecture is open.
- **Review cadence and stakeholder model.** Quarterly review with product? Monthly with engineering leadership? Per-workload.

## How deferred decisions get made

- Manifest-schema additions ship in a follow-up ADR amending [ADR 0011 (module manifest)](./0011-module-manifest.md), once at least one workload's SLO declaration is real.
- The tooling decision is its own ADR with a procurement / build-vs-buy comparison.
- Per-workload targets and policies are documented in each workload's onboarding RFC, not in platform ADRs.
- Default templates (if any) ship as a docs PR (`docs/slo-templates.md`) once a few real workloads have shaken out the patterns.

## Reversibility

**Cheap to change (two-way door) — and deliberately so, because the platform owns only the framework.** The SLI definitions, dashboard plumbing, and error-budget *mechanism* are platform-provided scaffolding that can be revised. The numeric targets and budget policies live with the workload teams, who can renegotiate them as a documented change. Nothing here destroys data or breaks a contract. The split itself — platform owns the framework, workload owns the numbers — is the one sticky commitment: reversing *that* would mean the platform team setting targets for services it does not operate, which this ADR rejects on principle, not for cost reasons.

## Consequences

**Positive.**

- The substrate gains consumers, not just collectors.
- Incidents become defensible: "we burned X% of budget; here is what we are doing" rather than "it felt slow."
- Workload teams own their service-level commitments — which is the only honest place for them to live.
- The platform's own services are held to the same discipline.

**Negative — and accepted.**

- SLOs done badly — numbers chosen without rigor, then never reviewed — are worse than no SLOs, because they create false confidence. The error-budget-as-real-lever stance is the offset; an SLO without an associated policy is theater.
- The platform team has to invest in SLI definition for each workload pattern. That work is not free.
- Some workloads have no good SLI candidates (e.g., a batch job that runs once a quarter). We accept that those workloads carry minimal SLO declarations, with documentation of why.

## Cites

- [AP-002](../anti-patterns.md#ap-002--telemetry-dumping-ground) — what this ADR partially prevents (the substrate as a dumping ground).
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — the substrate provides the data SLOs measure against.
- [ADR 0013](./0013-platform-metrics-and-dora.md) — DORA metrics measure the *platform's* delivery; SLOs measure individual *workloads'* service quality.
- *Site Reliability Engineering* (the Google SRE Book), particularly chapters 4–6 on SLOs and error budgets.
- *The Site Reliability Workbook*, chapter 5, on multi-window multi-burn-rate alerting.
