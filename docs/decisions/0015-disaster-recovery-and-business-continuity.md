---
id: 15
title: Disaster recovery is per-workload; the platform provides the primitives
status: accepted
date: 2026-04-27
categories: [governance, security, foundation]
supersedes: []
superseded_by: []
cites_anti_patterns: []
cites_adrs: [ADR-0007, ADR-0010]
---

# ADR 0015 — Disaster recovery is per-workload; the platform provides the primitives

## Context

For a regulated financial-services organization, a documented disaster-recovery (DR) and business-continuity (BCP) posture is not optional — examiners ask for it, members depend on it, and the incident that clarifies "we should have thought about this" is the wrong incident to learn from.

A common failure mode: DR exists on paper as a binder nobody has read, with RTO/RPO targets nobody can defend, and a restore procedure nobody has practiced. The opposite failure mode is also common: every workload reinvents its own DR from scratch, and the platform provides no consistent primitives, so DR posture varies wildly across the estate.

The right shape: **the platform standardizes the primitives that make DR achievable; workload teams declare and own their RTO/RPO targets; restore drills are a real practice, not a checkbox.**

This ADR captures the **discipline** — that DR is per-workload, the platform provides primitives, and drills are real. The **specific RTO/RPO targets** are explicitly the workload-team's decision, in conversation with risk and the relevant business stakeholder.

## Decision

### 1. Every workload pattern declares RTO and RPO targets per environment

- **RTO (Recovery Time Objective)** — maximum acceptable downtime after a disaster.
- **RPO (Recovery Point Objective)** — maximum acceptable data loss measured in time (e.g., "no more than 15 minutes of writes").

v0.1.0 manifests do not yet require an `rto`/`rpo` field — the schema addition is deferred until per-workload structure is decided. When the field arrives, every production-tier workload must populate it; lower tiers are encouraged.

The targets are workload-team decisions. The platform team's role is to ensure the *primitives* (geo-redundancy, backup, restore tooling) make achieving the declared targets possible.

### 2. The platform provides DR primitives; workloads compose them

Foundation- and platform-services-level modules expose:

- Geo-redundancy options for the storage primitives that support it (Storage, Cosmos, SQL).
- Backup configuration as inputs (retention, geo-replication of backups, immutable-backup flags).
- Region-pair declarations consistent across the estate (paired-region semantics for Azure region pairs; documented exceptions).
- A standardized backup-naming and tagging convention so backups are findable in an actual incident.

What the platform does **not** do: pick the per-workload RTO/RPO. That depends on business impact, stakeholder appetite, and cost — none of which the platform team owns.

### 3. Restore drills are a real practice

A backup that has not been restored is not a backup; it is an unverified hope. Production-tier workloads drill restore at least annually, in a non-production environment, with the result captured in the deployment ledger from [ADR 0007](./0007-change-as-code.md).

Drill participation is a workload-team responsibility; the platform team provides drill tooling and the restore procedures for the primitives it ships.

### 4. The platform's own DR is in scope

The platform itself is a service. The substrate (LAW), the policy-evaluation infrastructure, the deploy identity and its associated secrets — all have RTO/RPO and drill expectations of their own. The platform team sets these for itself; they are not deferred to workload teams.

### 5. Region pairing is a deliberate decision per environment

Azure paired regions have specific update-domain and recovery semantics. The platform's choice of primary and DR regions is a per-environment decision (likely consistent across environments, but possibly not — a sandbox environment may not warrant DR pairing at all). The decision is captured per environment in the environment's root config, with the rationale.

## What this does not decide

- **Manifest-schema shape.** The `rto:` and `rpo:` fields in `manifest.yaml`. Likely per-environment objects (e.g., `rto: { prod: 4h, staging: 24h, dev: best_effort }`), but exact shape deferred until at least one workload has a real declaration.
- **Default RTO/RPO suggestions per business-criticality tier.** Reasonable starting points exist (tier-0 = minutes, tier-3 = days), but the platform team should not declare these without input from risk, the relevant business stakeholder, and the impacted workload teams. Suggested *defaults* may eventually live in `docs/dr-templates.md`; *targets* always come from the conversation with the team.
- **Region-pair selection.** WSECU's Azure region footprint is small (likely 1–2 regions). The choice of primary/DR pair is environment-specific and depends on data-residency, latency, and cost considerations not yet collected.
- **Backup tooling.** Azure Backup vs Azure Site Recovery vs vendor (Veeam, Commvault) vs database-native (SQL geo-replication, Cosmos multi-region writes, etc.). Likely a mix; the choice per primitive is a follow-up ADR.
- **Drill cadence and scope.** Annual is the minimum stated above. Whether tier-0 workloads drill more often (quarterly?), whether platform-level DR drills are coordinated with workload drills, etc. — deferred.
- **BCP integration.** The DR posture in this ADR is technical. Business Continuity (people, processes, communication, member-facing services) is broader. Integration with the org-level BCP plan is a separate conversation that this ADR is the technical input to.
- **Compliance evidence shape.** Auditors want artifacts: drill records, RTO/RPO declarations, backup-retention proof. The substrate has the data; the *evidence pack* shape is a follow-up.

## How deferred decisions get made

- Manifest-schema additions ship in a follow-up ADR amending [ADR 0011 (module manifest)](./0011-module-manifest.md), once at least one workload's RTO/RPO declaration is real.
- Region-pair selection ships per environment in that environment's root config, not in a platform ADR.
- Backup-tooling decision is a follow-up ADR with a procurement / build-vs-buy comparison per primitive.
- Drill cadence and BCP integration are documented in `docs/dr-runbook.md` (future) and reviewed with risk leadership at least annually.
- Compliance-evidence shape is its own follow-up, likely after the first audit cycle gives concrete feedback.

## Reversibility

**Mostly cheap to change (two-way door); two parts are load-bearing.** The discipline — workloads own RTO/RPO, the platform provides primitives, drills are real — is a posture that can be adjusted per workload through ordinary change. The two stickier parts: (1) **region-pair selection**, once data lands in a primary/DR pair, is expensive to re-home (a data-migration project, not a config flip), which is why the ADR pushes it into per-environment root config where it is decided with eyes open; and (2) the **platform's own DR commitments** for the substrate and deploy identity, which downstream workloads implicitly depend on. Everything else — targets, tooling, cadences — is explicitly deferred and revisable.

## Consequences

**Positive.**

- DR has a vocabulary, a discipline, and a place where decisions live.
- Workload teams own their RTO/RPO — which is the only honest place for those to live.
- The platform's primitives are reviewed for "does this make the declared RTO achievable?" rather than for "did we tick the DR box?"
- Restore drills move from theater to practice; backup quality becomes measurable.
- Auditor questions about DR have specific answers, not "we have a binder somewhere."

**Negative — and accepted.**

- DR primitives have real cost (geo-redundancy doubles storage cost; cross-region writes add latency). Workloads that declare aggressive RTO/RPO targets pay for them. We are explicit that DR is a tradeoff, not a free safety net.
- Restore drills consume engineering time. We accept that; an unverified backup is no backup.
- The "platform provides primitives, workload owns targets" split requires workload teams to think seriously about RTO/RPO, which some teams may resist. The alternative — platform team picks the targets unilaterally — is worse.

## Cites

- [ADR 0007](./0007-change-as-code.md) — drill records flow through the deployment ledger.
- [ADR 0010](./0010-tag-taxonomy.md) — `business-criticality` tag is the suggested default-target driver, when defaults eventually exist.
- FFIEC IT Examination Handbook — Business Continuity Management — the regulatory anchor for credit unions.
- Google SRE Book chapter on disaster recovery testing — the source of the "unverified backup is not a backup" framing.
