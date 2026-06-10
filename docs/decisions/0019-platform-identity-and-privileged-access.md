---
id: 19
title: Platform identity and privileged access — groups, just-in-time elevation, break-glass
status: proposed
date: 2026-06-09
categories: [foundation, security, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-006, AP-007]
cites_adrs: [ADR-0007, ADR-0009, ADR-0012, ADR-0020, ADR-0024]
---

# ADR 0019 — Platform identity and privileged access — groups, just-in-time elevation, break-glass

> **Status: draft RFC.** Open for comment per [ADR 0012](./0012-collaborative-design.md); the default two-week comment period applies, longer if the affected teams want it. Nothing below is final until the security-affected teams sign off — and several specifics here (group names, approver lists, conditional-access details) are explicitly the adopter's to fill in even after acceptance.

## Context

The platform has a strong *workload* identity story — applications and the pipeline prove who they are with short-lived tokens, and no stored passwords exist ([ADR 0009](./0009-secrets-ephemeral-by-default.md), [ADR 0020](./0020-cicd-azure-devops-pipelines.md)). What it does not yet have is a decided *human* identity story: how people get access, how much they hold at rest, how they elevate when something genuinely needs hands, and what happens when the normal paths are down.

Pieces of the answer are already scattered through accepted decisions: [ADR 0007](./0007-change-as-code.md) says humans are read-only in production and elevation goes through **PIM** (Privileged Identity Management — Azure's "check out elevated rights for a bounded time, with a logged reason" feature) with a captured back-fill; the firmitas review rule demands least-privilege RBAC. But "mentioned in passing" is not a decision, and for a credit union this is prime examiner territory: who can touch member-data infrastructure, how that access is bounded, and what the audit trail shows.

This ADR consolidates the human-access model into one decision. It decides the *shape*; the adopter's real groups, people, and approver lists are deferred values, consistent with the whole foundation ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)).

## Decision

### 1. Access flows through Entra ID groups, never direct user assignments

Every Azure RBAC role a human holds is granted to an **Entra ID group** (the directory's team construct), and people get access by group membership. Direct user-to-role assignments are forbidden — they are the access-control version of hand-edited infrastructure: invisible to review, immortal by default, and unanswerable at audit time ("who can touch production?" should be a group-membership query, not an archaeology project).

Group design follows the scope vocabulary of ADR 0024: a small set of platform-level groups (platform engineers, security readers, break-glass operators) plus per-team workload groups, each mapped to roles at the *narrowest scope that works* — workload resource group before subscription, subscription before management group.

### 2. Standing access is read-only; privilege is checked out, not held

The resting state for every human, including platform engineers, is **Reader** in production. Anything that changes production goes through the pipeline ([ADR 0007](./0007-change-as-code.md)) — humans don't apply Terraform, the deployment identity does.

When a human genuinely needs write access — incident response, an investigation the portal serves better than code — they elevate through **PIM**: the privileged role is *eligible*, not active; activation requires a reason and fresh multi-factor authentication; it expires on a short clock (default 4 hours, 8 maximum); and high tiers (Owner or Contributor at subscription scope and above, in production) additionally require a named approver who is not the requester. Every activation is logged, and any change made while elevated is captured back into code within 24 hours per ADR 0007's break-fix rule.

> **In plain terms:** nobody walks around with the master keys in their pocket. The keys live in a logbook cabinet; you sign one out with a reason, it stops working in a few hours, and someone else countersigns for the dangerous ones. The pipeline — not a person — does the routine driving.

### 3. Break-glass: two accounts, heavily guarded, loudly monitored

Normal access depends on Entra ID, conditional access, MFA devices, and PIM all working. When they don't — a federation outage, a conditional-access lockout — the estate still needs a way in. Two **break-glass accounts** exist: cloud-only (no dependence on federation or on-premises infrastructure), excluded from conditional-access policies, holding standing Global Administrator / Owner rights, with long random credentials stored outside the identity system itself (sealed, physically controlled, split if the adopter's policy requires it).

The compensating control is noise: any sign-in by a break-glass account fires a high-severity alert from day one (the same protect-the-watchers carve-out as [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) §3 — this is one of the few controls that never starts in watch-only mode), automatically opens an incident, and triggers the ADR 0007 capture path for anything changed. The accounts are verified quarterly — credentials still work, alert still fires — because an untested break-glass account is the disaster-recovery lie of the identity world.

### 4. Separation of duties is structural, not aspirational

Four seams, each enforced by mechanism rather than memo:

- **Author ≠ approver.** Already ADR 0007; restated here as an identity property: the approval gate checks identity, and self-approval is rejected.
- **Humans plan, the pipeline applies.** People (and their groups) hold no standing write access that would let them bypass the deployment path; the OIDC pipeline identity ([ADR 0020](./0020-cicd-azure-devops-pipelines.md)) is the only routine writer.
- **The deployer cannot rewrite the rules.** The pipeline identity holds resource-level rights only — it cannot edit Azure Policy assignments, RBAC, or its own permissions. Changing the guardrails is a separate, human-approved path.
- **Security reviews access; platform grants it.** Group-membership changes for privileged groups require a security-team approver; quarterly **access reviews** (Entra ID's built-in recertification) confirm membership is still warranted, and unreviewed membership lapses rather than persisting.

## What this does not decide

- **The actual group catalog and role mappings** — group names, which roles at which scopes, and the approver lists are the adopter's organization, filled in at adoption like every other real-world value (ADR 0024).
- **Conditional-access policy content** — device compliance, location rules, and session controls are tenant-level security policy owned by the adopter's security team; this ADR assumes their existence, not their shape.
- **PIM tier specifics** — which roles are eligible-vs-active per environment, exact activation windows, and approver assignments are tuned with the security partners during the RFC period and after real use.
- **Tooling for access-review evidence** — quarterly is the stated default; the evidence-pack shape feeds the ADR 0021 machinery and is a follow-up.
- **Workload identity** — already decided (ADR 0009); this ADR is about humans.

## Reversibility

**Mostly two-way doors, with one one-way ratchet.** Group mappings, PIM windows, and approver lists are configuration — change them freely as the org learns. The one-way part is the *posture*: once standing write access is revoked and the estate runs on checked-out privilege, walking back to standing admin rights is technically trivial and culturally corrosive — every exception erodes the audit story that read-only-by-default buys, and regulators notice ratchets loosening. Reverse direction (tightening) stays cheap, which is the direction that matters.

## Consequences

**Positive.**

- "Who can touch production?" becomes a group query with a quarterly-reviewed answer — examiner-ready by construction.
- Privileged access is bounded in time, attributed, reasoned, and logged; the PIM activation log plus the deployment ledger covers both halves of "who changed what."
- Identity outages have a tested, monitored escape hatch instead of an improvised one.
- The model composes with what's already decided rather than adding a parallel system: ADR 0007 supplies the change path, ADR 0009/0020 the non-human identities, ADR 0021 the evidence plumbing.

**Negative — and accepted.**

- Checked-out privilege is slower than standing admin rights, by design. The friction is the control; incidents that genuinely can't wait have break-glass.
- PIM approvals add an on-call duty for approvers of the highest tiers.
- Break-glass accounts are standing super-credentials — the exact thing the rest of the ADR eliminates. They are accepted because the alternative (no path when identity infrastructure fails) is worse, and they are wrapped in the loudest monitoring in the estate.

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — elevation is captured back to code, never silent.
- [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil) — humans hold no standing secrets either; privilege expires like tokens do.
- [AP-007](../anti-patterns.md#ap-007--change-management-theater) — separation of duties enforced by mechanism, not by meeting.
- [ADR 0007](./0007-change-as-code.md) — the change path this access model funnels everyone into.
- [ADR 0009](./0009-secrets-ephemeral-by-default.md) — the non-human half of the identity story.
- [ADR 0012](./0012-collaborative-design.md) — this ships as an RFC; security-affected teams sign off.
- [ADR 0020](./0020-cicd-azure-devops-pipelines.md) — the pipeline identity that does the routine writing.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — the scope vocabulary group mappings bind to.
