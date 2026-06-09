---
id: 8
title: Audit-before-Deny policy lifecycle; exemptions are first-class
status: accepted
date: 2026-04-26
categories: [security, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-005]
cites_adrs: [ADR-0003, ADR-0005, ADR-0007]
---

# ADR 0008 — Audit-before-Deny policy lifecycle; exemptions are first-class

## Context

A **policy** here is an automated rule enforced across the cloud estate ("no public IPs anywhere"). [AP-005 — Sweeping policy bans](../anti-patterns.md#ap-005--sweeping-policy-bans) is what happens when those rules are written too broadly: blanket bans like "no VMs allowed" block legitimate experimentation, push engineers to **shadow IT** (unmanaged personal accounts outside the platform's view), and rarely match the actual security threat. The opposite failure — no policy at all — is unacceptable in a regulated environment.

The right path is policy that is scoped, justified, evidence-based, and has a documented exemption workflow. This ADR specifies the lifecycle every Azure Policy in this repo follows. (**Azure Policy** is Azure's built-in system for automatically checking and enforcing rules on resources; its two key modes are `Audit` — watch and report violations, block nothing — and `Deny` — actually block.)

## Decision

### 1. Author with intent

Policies are grouped into Azure Policy **Initiatives** — named bundles of related policies. The initiative documents:

- The intent: what the policy bundle is trying to achieve, in plain English.
- The controls it maps to — the NIST CSF subcategory, the GLBA Safeguards Rule section, the internal risk register entry (the regulatory requirements this rule exists to satisfy).
- The expected impact and the engineering teams affected.

A bare policy assignment outside an initiative is forbidden by convention.

### 2. Audit before Deny

Every new enforcement starts in `Audit` mode for 30–90 days: it watches and reports what it *would* have blocked, without blocking anything. That telemetry feeds the observability substrate — our central monitoring pipeline ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)) — and the data informs whether `Deny` is safe. Promotion to `Deny` requires a PR that cites the Audit-mode evidence: how many resources would have been blocked, who owns them, and whether the policy is achieving its intent without false positives.

### 3. Tiered enforcement

Sandbox and dev tiers run `Audit` indefinitely for the same policy; production runs `Deny` once the audit data supports it. Engineers experiment in sandbox without fighting the rules; production gets the protection.

The exception: policies that protect *the substrate itself* — preventing deletion of platform resources or of the audit logs — run `Deny` everywhere from day one. The substrate is not a fair target for experimentation.

> **In plain terms:** before installing a gate that locks, put up a camera for a month and see who actually walks through and why. Then decide whether to lock it, where, and who gets a key — and keep a fast key-request process so nobody climbs the fence.

### 4. Exemptions are first-class

An **exemption** is an approved, recorded exception to a policy. Azure Policy supports them natively, with expiry dates, justification, and approver. Exemptions are reviewed quarterly; expired exemptions auto-close. Engineers requesting one follow a documented workflow that is faster than working around the policy. Specifically:

- **Time-boxed.** Default expiry is 90 days; renewals require re-justification.
- **Owner-attributed.** The exemption attaches to a team, not a person.
- **Auditable.** Exemption events emit to the substrate; long-lived exemptions trigger review alerts.
- **Documented.** The exemption record points at an ADR or ticket explaining the deviation.

### 5. Modules ship their initiatives

Per [ADR 0003](./0003-modules-ship-policy-and-monitoring.md), modules in this repo ship their own policy in `policy/`. Initiative scope is documented at the module level. Assignment scope — where the rule actually applies (management group, subscription, resource group) — is set at the consumer boundary, not inside the module. Modules don't decide where they apply.

### 6. Policy changes follow the same lifecycle as code

Adding, modifying, or removing a policy is a PR ([ADR 0007](./0007-change-as-code.md)). Promoting a policy from `Audit` to `Deny` is a normal change with required security-team review.

## What this does not decide

- **The actual policies and their control mappings** — which initiatives exist and how they map to NIST CSF / GLBA is deferred to the `policies/ncua-glba` work with security/compliance partners, and to each module's own `policy/`.
- **The exact Audit window per policy** — 30–90 days is a range; the specific dwell time is set per policy from its evidence.
- **Assignment scope** — where an initiative is assigned (management group / subscription / resource group) is the consumer-boundary's call (§5), governed by the landing-zone decision.

## Reversibility

**Cheap to change (two-way door) — it is a governance process, not infrastructure.** The lifecycle (Audit → Deny, tiered enforcement, first-class exemptions) is a workflow; adjusting a window, flipping an individual policy from `Deny` back to `Audit`, or revising the exemption cadence is a PR with low blast radius and no data loss. The one sticky part is cultural, not technical: teams come to rely on "sandbox stays in Audit," so removing that expectation would be disruptive even though it is mechanically trivial. Nothing here is a one-way door.

## Consequences

**Positive.**

- Policy outcomes are evidence-based; surprises are caught in `Audit` before they break production.
- Engineers can experiment in lower environments without fighting the rules.
- Exemptions are documented, time-limited, and audit-friendly. Auditors see *why* a deviation exists, *when* it expires, and *who owns* it.
- Initiative-level intent documentation answers auditor questions about *why* a policy exists, not just *what* it does.
- Promotion-by-evidence prevents well-meaning policies from breaking production.

**Negative — and accepted.**

- Audit-mode telemetry adds substrate cost. That cost is a fraction of the cost of a `Deny`-mode policy that breaks production.
- Some teams prefer "ban it now, deal with consequences later." We push back; the consequences are the cost.
- Tiered enforcement means production has a stricter posture than sandbox, so code that runs cleanly in sandbox can fail in production. We treat this as a feature: production-fidelity validation is the workload-pattern test job's responsibility, not a per-engineer surprise.
- The 90-day exemption expiry creates renewal toil for a small number of long-lived exceptions. The toil is intentional: if an exemption is permanent, the policy is wrong.

## Cites

- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — what this ADR prevents.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — modules ship their initiatives.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — Audit-mode telemetry feeds the substrate.
- [ADR 0007](./0007-change-as-code.md) — policy changes follow change-as-code.
