---
id: 12
title: Collaborative design — practices that prevent design-in-vacuum
status: accepted
date: 2026-04-26
categories: [process, culture]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-012, AP-005, AP-007, AP-010]
cites_adrs: [ADR-0007, ADR-0008]
---

# ADR 0012 — Collaborative design — practices that prevent design-in-vacuum

## Context

[AP-012 — Seagull architecture](../anti-patterns.md#ap-012--seagull-architecture) is the failure mode where an architect designs in isolation, swoops in, drops edicts on engineers, and flies away. Several technical anti-patterns this repo guards against — sweeping policy bans ([AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans)), change-management theater ([AP-007](../anti-patterns.md#ap-007--change-management-theater)), no golden paths ([AP-010](../anti-patterns.md#ap-010--no-golden-paths)) — share that same upstream cause: design done in a vacuum, away from the people who live with the result.

The practices that prevent it cannot be enforced by the repo; they are commitments about how people behave. But they *can* be made explicit, visible, and reviewable — which is what this ADR does.

## Decision

The platform team commits to the following design practices. The repo is the artifact; the practices are the behavior.

### 1. RFC-style ADR drafting

Non-trivial ADRs ship first as draft pull requests with a defined **RFC period** — a "request for comments" window during which the draft is open to feedback (default two weeks for normal scope; longer for changes that cut across teams). Any engineer on any team affected by the decision can comment. Merging requires sign-off from reviewers on the affected teams, not only from the architect.

The architect can author an ADR; the architect cannot self-approve it.

### 2. Pattern lifecycle: alpha → beta → GA

A new workload pattern (or any reusable opinion) matures through three stages, recorded in the module's `manifest.yaml` as `metadata.status`:

- **Alpha** (`status: experimental`) — the author has built it; one team is invited to try it.
- **Beta** (`status: beta`) — at least one team has shipped on it and reported back; rough edges are documented and addressed.
- **GA** (`status: stable`) — "general availability": the pattern has at least two consumers, and the platform team can stand behind how it behaves in operation.

No pattern goes straight from the architect's keyboard to "platform standard" without crossing this gate. A pattern that fails to graduate within a documented timeframe is revisited, revised, or deprecated.

### 3. Public design surface

Architecture discussions happen in pull-request comments, GitHub issues, or team-wide chat channels — never in direct messages or closed meetings. Both the decision and the *reasoning* stay reviewable later. If a decision does get made in a meeting, a written record lands as a PR or comment within 24 hours.

### 4. Embedded rotation

The architect rotates through workload teams as a working contributor — actually shipping features, reviewing code, and (where appropriate) taking on-call shifts — on a cadence each team agrees to. The architect does not become any team's principal engineer during a rotation; the goal is contact with reality, not co-option.

### 5. Office hours

Regular scheduled slots where engineers bring problems and the architect helps think them through as a peer, not as an approver. Office hours gate nothing; they exist to shorten the loop between "an engineer hits a question" and "the platform shapes its opinion."

### 6. Open contribution

Anyone can propose a module, an ADR, or an anti-pattern. The contribution path is documented in [`CONTRIBUTING.md`](../../CONTRIBUTING.md). The architect's role is to curate and synthesize, not to gate who gets to write.

### 7. Deviations are signals

Per [`docs/golden-paths.md`](../golden-paths.md), deviating from a workload pattern requires an ADR. The platform team reads those ADRs as feedback: when many teams deviate from a pattern, the pattern is wrong — not the engineers. Deviation rates are reviewed quarterly.

### 8. Engineer-blocker pause

If an engineer raises a concrete technical blocker against a draft pattern, ADR, or policy promotion, the work pauses until the concern has been engaged on its merits. *"That's not the way we're going"* is not an answer; *"here is why your concern does not apply here"* is.

### 9. Every ADR declares what it defers and how reversible it is *(added 2026-06-01)*

Two sections are **required** in every ADR and present in [`_template.md`](_template.md):

- **What this does not decide** — the specifics deliberately left open, named explicitly. The platform is a reference foundation that organizations adopt in whole or in part, often before the adopter's real infrastructure is known. Decide the *contract and shape*; defer the *concrete values, topology, and vendor choices* to the adopter or to a follow-up decision.
- **Reversibility** — classify the decision as cheap-to-change (a two-way door: a config or interface change with a small blast radius) or load-bearing (a one-way door: other modules or external contracts depend on it), and state what it would cost to unwind.

The point is to make every decision declare its blast radius, keep the line between reference design and real infrastructure visible to any adopter, and stop the platform from being locked into corners by decisions that only looked cheap. Both sections are additive, cost nothing, and are enforced by review, not tooling — consistent with the rest of this ADR.

## What this is not

This ADR does not commit the platform team to design-by-consensus. The team's job is still to *commit to opinions* on cross-cutting concerns — see [`docs/golden-paths.md`](../golden-paths.md). The discipline is: gather input widely, then synthesize it into a clear opinion. Failing to gather is the seagull anti-pattern; failing to commit is the no-golden-paths anti-pattern. This ADR addresses the first; the golden-paths doc addresses the second.

## What this does not decide

- The concrete RFC period, embedded-rotation cadence, and office-hours frequency. These are per-team agreements; the defaults above are starting points, not mandates.
- The forum tooling for the public design surface (which chat platform, how issues are organized) — that is process, not platform.
- How reviewer sign-off is recorded and enforced mechanically — left to the repo's CI / branch-protection setup (a follow-up decision).

## Reversibility

**Cheap to change (two-way door).** Every practice here is a behavioral commitment, not infrastructure. Adjusting a cadence, an RFC period, or a forum is a doc edit and a team conversation, with zero blast radius on any shipped module. Nothing technical depends on these practices. The only real cost of reversing them is cultural: dropping them re-opens the door to the seagull anti-pattern ([AP-012](../anti-patterns.md#ap-012--seagull-architecture)) this ADR exists to close.

> **In plain terms:** none of this is enforced by a machine. It is a published promise about how the team designs — and publishing it *is* the enforcement, because lapses become visible.

## Consequences

**Positive.**

- Sweeping policies (AP-005) get caught at the draft stage, because affected teams comment before anything is promoted.
- Change-management theater (AP-007) shrinks, because controls are visible in PR review instead of being papered over by ceremony.
- Golden paths (AP-010) emerge from real use rather than from speculation.
- Trust between platform and product teams is built on visible practice, not asserted by the org chart.
- New engineers see the design conversation, not just the conclusion — onboarding is faster.

**Negative — and accepted.**

- ADR-by-RFC takes longer than ADR-by-decree. We accept the latency in exchange for decision quality.
- Embedded rotation costs the architect deep-work time. We accept the cost; an architect who never ships isn't a platform architect, they're a slide deck.
- Office hours and a public design surface require ongoing investment. We accept the cost; the alternative is design-in-vacuum.
- This ADR is enforceable only by the platform team's own discipline. We accept that the practices are commitments, not enforcement, and we keep them visible so lapses are noticed.

## Cites

- [AP-012](../anti-patterns.md#ap-012--seagull-architecture) — what this ADR exists to prevent.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — caught at RFC review.
- [AP-007](../anti-patterns.md#ap-007--change-management-theater) — a public design surface beats change-advisory-board (CAB) ceremony.
- [AP-010](../anti-patterns.md#ap-010--no-golden-paths) — the alpha/beta/GA lifecycle ensures patterns emerge from use.
- [ADR 0007](./0007-change-as-code.md) — change-as-code complements the public design surface.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — audit-mode telemetry is the policy version of "deviations as signals."
