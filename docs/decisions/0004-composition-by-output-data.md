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

Module libraries tend to grow a "middle tier" of orchestrator modules — a `landing-zone` module that calls a `networking` module that calls a `hub` module that calls a `firewall` module. Each layer adds its own opinions, parameters, and bug surface; consumers end up wiring values four layers deep through `module.foo.module.bar.module.baz.outputs.x` plumbing.

The consequence is component sprawl: every cross-cutting change requires touching multiple orchestrators, each abstraction is leaky, and the consumer has lost a meaningful sense of what is actually being deployed.

## Decision

**Modules in this repo do not import each other.** Composition happens exclusively at the *consumer* boundary — an example, an environment root, or a workload-team's own Terraform.

A consumer instantiates Module A, reads its outputs, and passes them as inputs to Module B. Modules expose their consumer contract via outputs — not by allowing siblings to reach into them.

We do **not** create orchestrator modules whose only purpose is to call other modules in this repo.

## Consequences

**Positive:**

- The consumer sees, at one level of indirection, exactly what is being deployed and how it is wired together.
- Changing one module does not ripple through three layers of orchestrators.
- Modules are independently testable and reviewable.
- Composition patterns that turn out to be common become **examples** in `examples/`, not new modules.

**Negative / things we accept:**

- Consumer roots are slightly more verbose than they would be with a top-level orchestrator.
- A team that wants "the whole stack in one module call" doesn't get one. Their alternative is to fork a relevant `examples/` consumer into their own root and trim it. We consider this an acceptable, even desirable, friction — it keeps the platform's opinion legible.
- Module authors must be disciplined about output design. Outputs are the contract; they cannot be added or removed casually.

## When the rule does not apply

AVM modules in `versions.tf` are *upstream* dependencies, not siblings. A module in this repo does declare `module "avm_xxx" { source = "Azure/..." }` — that is the whole point of anchoring on AVM. The rule prohibits a module in this repo from depending on *another module in this repo*.
