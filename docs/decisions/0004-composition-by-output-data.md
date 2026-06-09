---
id: 4
title: Composition is by output data; no orchestrator modules
status: accepted
date: 2026-04-26
categories: [foundation, architecture]
supersedes: []
superseded_by: []
cites_anti_patterns: []
cites_adrs: []
---

# ADR 0004 — Composition is by output data; no orchestrator modules

## Context

Module libraries tend to grow a "middle tier" of **orchestrator modules** — manager modules whose job is to call other modules: a `landing-zone` module that calls a `networking` module that calls a `hub` module that calls a `firewall` module. Each layer adds its own opinions, parameters, and bug surface, and consumers end up threading values four layers deep through `module.foo.module.bar.module.baz.outputs.x` plumbing.

The consequence is component sprawl: every cross-cutting change touches multiple orchestrators, each abstraction leaks, and the consumer loses any real sense of what is actually being deployed.

## Decision

**Modules in this repo do not import each other.** Composition — wiring modules together into a working system — happens exclusively at the *consumer* boundary: an example, an environment root (the Terraform configuration that actually deploys a given environment), or a workload team's own Terraform.

The consumer instantiates Module A, reads its **outputs** (the values a module hands back, such as the ID of a network it created), and passes them as inputs to Module B. A module's outputs are its contract with consumers — sibling modules do not reach into each other.

We do **not** create orchestrator modules whose only purpose is to call other modules in this repo.

## What this does not decide

- **How a consumer structures its root** — single root vs per-environment vs per-workload is the consumer's call; `examples/reference-landingzone` is the worked reference, not a mandate.
- **The exact module/consumer boundary for edge cases** — where "this is a module" ends and "this is a consumer" begins is judged per case (`docs/composition.md`), not fixed here.
- **Upstream AVM nesting** — depending on `Azure/...` AVM modules is explicitly *not* a violation (see "When the rule does not apply").

## Reversibility

**Load-bearing (a one-way door) — and an asymmetric one.** Reversing this is *mechanically* trivial: nothing stops someone adding an orchestrator module tomorrow, and doing so breaks no existing module. But it is *strategically* one-way: once orchestrators exist they attract more orchestrators, and the component sprawl this ADR prevents compounds until it is expensive to unwind. The cost is not in the first reversal but in recovering from where it leads — which is exactly why the rule is guarded by code review rather than by tooling. To undo it, no existing code would change; what changes is every future module's design assumption and the review discipline that keeps contracts output-only.

> **In plain terms:** snap the building blocks together yourself, out in the open, so the finished assembly stays visible. Don't build a hidden block whose job is to assemble the others behind your back — the convenience isn't worth losing sight of what you built.

## Consequences

**Positive:**

- The consumer sees, at one level of indirection, exactly what is being deployed and how it is wired together.
- Changing one module does not ripple through three layers of orchestrators.
- Modules are independently testable and reviewable.
- Composition patterns that turn out to be common become **examples** in `examples/`, not new modules.

**Negative / things we accept:**

- Consumer roots are slightly more verbose than they would be with a top-level orchestrator.
- A team that wants "the whole stack in one module call" doesn't get one. Their alternative is to fork a relevant `examples/` consumer into their own root and trim it. We consider this an acceptable, even desirable, friction — it keeps the platform's opinion legible.
- Module authors must design outputs with discipline. Outputs are the contract; they cannot be added or removed casually.

## When the rule does not apply

AVM modules declared in `versions.tf` are *upstream* dependencies, not siblings. A module in this repo does declare `module "avm_xxx" { source = "Azure/..." }` — that is the whole point of anchoring on AVM. The rule prohibits a module in this repo from depending on *another module in this repo*.
