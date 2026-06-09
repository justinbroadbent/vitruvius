---
id: 24
title: Vitruvius binds to Azure Landing Zones by role; scopes are a named vocabulary, not a hierarchy we own
status: accepted
date: 2026-06-08
categories: [foundation, architecture, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-005]
cites_adrs: [ADR-0001, ADR-0003, ADR-0004, ADR-0005, ADR-0008, ADR-0010]
---

# ADR 0024 — Vitruvius binds to Azure Landing Zones by role; scopes are a named vocabulary, not a hierarchy we own

## Context

Vitruvius sits on top of Azure Landing Zones. Modules and policy initiatives have to land somewhere in a management-group / subscription / resource-group tree, and they have to refer to a scope they do not own. The forces:

- An adopter already has a tenant, very likely an existing ALZ deployment, and a management-group hierarchy shaped by their own org. Vitruvius must not invent a competing hierarchy or a `landing-zone` orchestrator module ([ADR 0004](./0004-composition-by-output-data.md)).
- "dev / staging / prod" appears throughout the repo ([ADR 0005](./0005-observability-substrate-and-signal-parity.md) signal parity, [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) tiered enforcement) with no decision on what an environment *is*.
- Policy-assignment scope is a per-module input today; a module that parses a scope string to guess subscription-vs-resource-group is brittle. [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) §5 leaves "where an initiative is assigned" to the landing-zone decision.

This ADR fixes the binding contract — the vocabulary by which modules attach to whatever ALZ tree exists — and leaves the tree itself to the adopter.

## Decision

### 1. Vitruvius binds to ALZ; it does not own the hierarchy

The management-group hierarchy — its depth, names, and the placement of the Platform and Landing Zone management groups — is ALZ's and the adopter's. Vitruvius defines how its modules attach to that tree, not the tree itself. There is no `landing-zone` module ([ADR 0004](./0004-composition-by-output-data.md)): the binding is data passed in at the environment-root boundary, not an orchestrator that calls siblings.

### 2. Scopes are referenced by role, as a small named vocabulary

A module that needs a scope declares it by role, never by hard-coded ID:

| Role | What it is | Supplied by |
|---|---|---|
| `platform_management_group` | The ALZ Platform MG (or the MG above the governed estate). Where estate-wide initiatives assign. | Adopter / ALZ |
| `landing_zone_management_group` | The MG above the workload subscriptions for one environment tier. Where per-environment initiatives assign. | Adopter / ALZ |
| `environment_subscription` | The subscription for one environment (§3). | Subscription vending (§5) |
| `workload_resource_group` | The RG a workload pattern deploys into; the audit-pilot scope. | Environment root |

Consumers resolve these roles to real IDs in the environment root and pass them as inputs. A module receives a resolved scope by role and does not parse a scope string to infer it.

### 3. An environment is a subscription boundary

The unit of environment isolation (`dev`, `staging`, `prod`, `sandbox`) is the subscription, placed under a landing-zone MG — the ALZ-native shape, giving each environment a clean RBAC, policy, and cost boundary. Signal parity across these subscriptions is [ADR 0005](./0005-observability-substrate-and-signal-parity.md); tiered enforcement is [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md). The boundary is the subscription; the count, IDs, and regions are not decided here.

### 4. Policy assignments default to management-group scope; narrower scope is the audit pilot

Modules ship initiatives but do not decide where they assign ([ADR 0003](./0003-modules-ship-policy-and-monitoring.md), [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md)). The canonical assignment scope is a management group, so an initiative covers every subscription beneath it. Subscription and resource-group scope remain first-class for the audit pilot — audit-before-deny often pilots on a single resource group, then promotes to MG-wide enforcement.

### 5. Subscription vending is assumed, not built

Vitruvius assumes the adopter's ALZ provides subscription vending and consumes its output — a subscription ID and the MG it is placed under — as environment-root input. No module provisions subscriptions.

### 6. The binding lives in the environment root, as code

Resolving roles (§2) to IDs and choosing assignment scopes (§4) happens in the environment root — a consumer ([ADR 0004](./0004-composition-by-output-data.md)) — checked into code ([AP-004](../anti-patterns.md#ap-004--configuration-drift)). The reference environment root that demonstrates this end-to-end is [`examples/reference-landingzone`](../../examples/reference-landingzone/), exercised in CI.

## What this does not decide

- **The concrete MG hierarchy** — depth, names, and the placement of the Platform / Landing Zone MGs are ALZ's and the adopter's. Modules bind by role (§2) so the same modules work against any conformant tree.
- **Subscription count, IDs, naming, regions, and address space** — adopter data, expressed in environment roots. Network address allocation is the networking layer's.
- **The subscription-vending mechanism** — assumed to be ALZ's (§5).
- **Tenant / Entra ID topology and multi-tenant estates** — out of scope; one tenant assumed unless an adopter ADR says otherwise.
- **RBAC / PIM binding at each scope** — who can act at a management group or subscription is platform-identity work.
- **The reference environment root itself** — the artifact that exercises the contract lives at [`examples/reference-landingzone`](../../examples/reference-landingzone/), outside this ADR.
- **The exact input-schema names** — the role vocabulary (§2) is fixed; how it surfaces (a `manifest.yaml` `semantic` hint, a shared variable convention, or a thin data module) is open.

## Reversibility

The scope vocabulary (§2) is load-bearing, and parameterization keeps it two-way per binding. Renaming a role or changing its meaning touches every consumer of it, so the vocabulary is kept small and additive, and binding is by role rather than by ID — any individual environment's resolution is a config change in its root with near-zero blast radius. The default-MG-scope rule (§4) is a per-assignment choice, and "environment = subscription" (§3) is a convention, not infrastructure. Undoing the load-bearing part means touching every module that takes a scope input plus the environment roots that resolve them.

## Consequences

**Positive.**

- Modules receive scopes by role, so they stop parsing scope strings to infer subscription-vs-resource-group (§2, §4).
- The same Vitruvius modules drop onto any conformant ALZ tree, because they bind by role rather than to a shipped hierarchy.
- Assignment scope has a defined home (§4, §6), and the audit-pilot-then-promote path is first-class.
- No orchestrator module; the binding is legible data in the environment root (ADR 0004), and it is code, not portal clicks (AP-004).
- Networking, identity, CI/CD, and the reference root have a defined notion of where to bind.

**Negative — and accepted.**

- Environment roots carry the resolution logic and are more verbose than a one-call landing-zone module. ADR 0004 already chose legibility over orchestration; the verbosity is the adopter's real topology made explicit.
- Binding by role assumes a conformant-enough ALZ. An adopter with a wildly non-standard hierarchy maps their tree onto the four roles themselves; the role set is small enough to map.
- The vocabulary is a contract to maintain as new scope-needing modules appear. It is small, additive, and cheaper than every module reinventing a scope input.

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — the binding is code in the environment root, not portal-applied scope.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — MG-default-with-RG-pilot keeps assignment scoped and evidence-based.
- [ADR 0001](./0001-iac-terraform-with-avm.md) — the estate is Terraform on AVM; scopes are inputs to that.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — modules ship initiatives; this ADR says where they assign.
- [ADR 0004](./0004-composition-by-output-data.md) — no orchestrator; the binding is consumer-boundary data.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — the assignment-scope decision left to the landing-zone decision.
- [ADR 0010](./0010-tag-taxonomy.md) — the tag initiative binds at MG scope.
