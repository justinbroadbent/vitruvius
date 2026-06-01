---
id: NNNN
title: <short statement of the decision, not the topic>
status: proposed # proposed | accepted | superseded
date: YYYY-MM-DD
categories: [] # e.g. [foundation, observability, security, governance, networking, process, culture]
supersedes: []
superseded_by: []
cites_anti_patterns: [] # e.g. [AP-001]
cites_adrs: [] # e.g. [ADR-0007]
---

<!--
Template for a Vitruvius ADR. Copy this file to `NNNN-kebab-title.md`, assign the
next sequential ID, and fill every section. Keep the frontmatter block first (the
index generator requires `---` on line 1). Drafts open as PRs with the
`kind:rfc-adr` label (ADR 0012). The two sections marked REQUIRED below are
non-negotiable — see ADR 0012 §9. This file is excluded from the generated index
because its name does not match the `NNNN-` pattern, so it is safe to keep here.
-->

# ADR NNNN — <title>

## Context

Why this decision is on the table, and the forces in tension. If the context is
not strong enough to justify a decision, the ADR is not ready (CONTRIBUTING.md).

## Decision

What we are deciding, stated plainly. Use numbered subsections for multi-part
decisions.

## What this does not decide

<!-- REQUIRED (ADR 0012 §9) -->

The specifics this ADR deliberately leaves open, **named explicitly** — concrete
values, topology, vendor choices, or downstream decisions that depend on
information not yet available (often the adopter's real infrastructure). Vitruvius
is a reference foundation adopted in whole or in part: decide the *contract and
shape* here; defer the *specifics* to the adopter or a follow-up. Optionally add a
short note on how each deferred item eventually gets decided (see ADR 0015 for the
pattern).

## Reversibility

<!-- REQUIRED (ADR 0012 §9) -->

Classify the decision and state the cost of unwinding it:

- **Cheap to change (two-way door)** — a config / variable / interface change with
  low blast radius. Bias toward shipping and iterating.
- **Load-bearing (one-way door)** — other modules, data, or external contracts
  depend on it; expensive to reverse. Justify the commitment, and name the
  optionality preserved (extension points, additive-only changes, parameterization
  at the consumer boundary).

State which this is and what would have to change to undo it.

## Consequences

**Positive.**

- ...

**Negative — and accepted.**

- ...

## Cites

- [AP-NNN](../anti-patterns.md#ap-nnn--slug) — ...
- [ADR NNNN](./NNNN-slug.md) — ...
