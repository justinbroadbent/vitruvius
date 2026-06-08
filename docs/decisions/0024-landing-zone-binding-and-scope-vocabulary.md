---
id: 24
title: Vitruvius binds to Azure Landing Zones by role; scopes are a named vocabulary, not a hierarchy we own
status: accepted
date: 2026-06-08
categories: [foundation, architecture, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-005]
cites_adrs: [ADR-0001, ADR-0003, ADR-0004, ADR-0008, ADR-0010]
---

# ADR 0024 — Vitruvius binds to Azure Landing Zones by role; scopes are a named vocabulary, not a hierarchy we own

## Context

The root `README.md` says "we sit on top of [Azure Landing Zones]" — but no ADR decides *how*. Three concrete gaps follow from that omission, and every other foundation seam waits behind them:

- **No management-group (MG) binding.** Modules and policy initiatives must land *somewhere* in an MG/subscription/resource-group tree, but nothing says where, or how a module refers to a scope it does not own.
- **No environment model.** "dev / staging / prod" appears throughout the repo (ADR 0005 signal parity, ADR 0008 tiered enforcement) with no decision on what an environment *is* — a subscription, an MG, a tag?
- **A live stopgap proving the gap.** `web-api-aks` accepts `policy_assignment_scope` as a raw string and sniffs whether it is a subscription or a resource group (`main.tf` `assign_at_subscription` / `assign_at_resource_group`). The inline comment already concedes the real answer is management-group scope. ADR 0008 §5 explicitly defers "where an initiative is assigned" to "the landing-zone decision" — this ADR.

The tension is the reference-foundation tension in its sharpest form. An adopter already has a tenant, very likely an existing ALZ deployment, and an MG hierarchy shaped by their own org. Vitruvius must **not** invent a competing hierarchy or a `landing-zone` orchestrator module ([ADR 0004](./0004-composition-by-output-data.md) forbids exactly that sprawl). But it also cannot leave "where things land" undefined, or every module grows its own ad-hoc scope-sniffing stopgap. The decision is to fix the **binding contract** — the vocabulary by which our modules attach to *whatever* ALZ tree exists — and defer the tree itself to the adopter.

## Decision

### 1. Vitruvius binds to ALZ; it does not own the hierarchy

We sit on top of Azure Landing Zones. The management-group hierarchy — its depth, names, and the placement of the Platform and Landing Zone management groups — is **ALZ's and the adopter's**, not ours. Vitruvius defines how its modules *attach* to that tree, never the tree itself. Consistent with [ADR 0004](./0004-composition-by-output-data.md), there is **no `landing-zone` module**: the binding is data passed in at the consumer (environment-root) boundary, not an orchestrator that calls siblings.

### 2. Scopes are referenced by role, as a small named vocabulary

A module that needs a scope declares it by **role**, never by hard-coded ID. The vocabulary is deliberately small:

| Role | What it is | Supplied by |
|---|---|---|
| `platform_management_group` | The ALZ Platform MG (or the MG above the estate Vitruvius governs). Where estate-wide initiatives assign. | Adopter / ALZ |
| `landing_zone_management_group` | The MG above the workload subscriptions for one environment tier. Where per-environment initiatives assign. | Adopter / ALZ |
| `environment_subscription` | The subscription for one environment (see §3). | Subscription vending (§5) |
| `workload_resource_group` | The RG a workload pattern deploys into; the audit-pilot scope. | Environment root |

Consumers resolve these roles to real IDs in the environment root and pass them as inputs. A module receives a resolved scope; it does not discover one. This **replaces the `web-api-aks.policy_assignment_scope` string-sniffing stopgap**: the scope's role is known by contract, so the module no longer guesses subscription-vs-RG from the string shape.

### 3. An environment is a subscription boundary

The unit of environment isolation (`dev`, `staging`, `prod`, `sandbox`) is the **subscription**, placed under a landing-zone MG. This is the ALZ-native shape and it gives each environment a clean RBAC, policy, and cost boundary. Signal parity across these subscriptions is ADR 0005's job; tiered policy enforcement across them is ADR 0008's. This ADR decides only that the **boundary is the subscription** — not how many there are, their IDs, or their regions.

### 4. Policy assignments default to management-group scope; narrower scope is the audit pilot

Per [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) and [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md), modules ship initiatives but do not decide where they assign. The **canonical** assignment scope is a **management group** (so an initiative covers every subscription beneath it). Subscription and resource-group scope remain first-class for the **audit pilot** — ADR 0008's audit-before-deny often pilots `Audit` on a single resource group, then promotes to MG-wide `Deny`. So the vocabulary keeps all three (MG / subscription / RG), with MG as the default home and the narrower scopes as the deliberate, documented pilot path — not a string the module has to parse.

### 5. Subscription vending is assumed, not built

Vitruvius assumes the adopter's ALZ provides subscription vending. We **consume its output** — a subscription ID and the MG it is placed under — as environment-root input. We do not build a vending machine, and no module provisions subscriptions. This keeps the foundation aligned with ALZ instead of competing with it.

### 6. The binding lives in the environment root, as code

Resolving roles (§2) to IDs, and choosing assignment scopes (§4), happens in the **environment root** — a consumer ([ADR 0004](./0004-composition-by-output-data.md)), checked into code like any other change ([AP-004](../anti-patterns.md#ap-004--configuration-drift)). The reference environment root that demonstrates this end-to-end is separate work (roadmap #7); this ADR fixes the contract that root will satisfy.

## What this does not decide

- **The concrete MG hierarchy** — depth, names, and where the Platform / Landing Zone MGs sit are ALZ's and the adopter's. We bind by *role* (§2) precisely so the same modules work against any conformant tree.
- **Subscription count, IDs, naming, regions, and address space** — adopter data, expressed in environment roots. The networking address-allocation and region-pair choices stay in the networking work (roadmap #8/#9), not here.
- **The subscription-vending mechanism** — assumed to be ALZ's (§5); we consume its outputs.
- **Tenant / Entra ID topology and multi-tenant estates** — out of scope; one tenant assumed unless an adopter ADR says otherwise.
- **RBAC / PIM binding at each scope** — *who* can act at a management group or subscription is platform-identity work (roadmap #10, the planned identity ADR), not this seam.
- **The reference environment root itself** — the artifact that proves the contract (roadmap #7) is separate; this ADR is the contract it implements.
- **The exact input-schema names** — the role vocabulary (§2) is decided; whether it surfaces as `manifest.yaml` input `semantic` hints, a shared variable convention, or a thin pure-logic data module is a follow-up, the same way ADR 0021's mapping field and ADR 0016's converter are separate from their contracts.

## Reversibility

**Load-bearing at the seam, but parameterized to stay two-way per binding.** The scope **vocabulary** (§2) is the one durable thing: it is what every module input and every policy assignment references, so renaming a role or changing its meaning touches every consumer of it — analogous to ADR 0016's naming scheme and ADR 0021's control-identifier vocabulary. We keep that cost bounded two ways: the vocabulary is **small and additive** (new roles can be added without disturbing existing ones), and binding is **by role, not by ID**, so any individual environment's resolution is a config change in its root with near-zero blast radius. The decisions *around* the vocabulary are cheap two-way doors: the default-MG-scope rule (§4) is a per-assignment choice, and "environment = subscription" (§3) is a convention, not infrastructure. What would have to change to undo the load-bearing part: every module that takes a scope input, plus the environment roots that resolve them — which is exactly why the vocabulary is worth deciding now, while almost nothing consumes it yet.

## Consequences

**Positive.**

- The `web-api-aks` scope-sniffing stopgap gets a real answer: roles are known by contract, so modules stop guessing subscription-vs-RG from a string (§2, §4).
- The same Vitruvius modules drop onto **any** conformant ALZ tree, because they bind by role rather than to a hierarchy we shipped — the whole reference-adopted-in-whole-or-part posture.
- ADR 0008's "assignment scope is the consumer's call" finally has a place to live (§4, §6), and the audit-pilot-then-promote path is first-class rather than incidental.
- No orchestrator module is introduced; the binding is legible data in the environment root (ADR 0004), and it is code, not portal clicks (AP-004).
- Every downstream seam — networking, identity, CI/CD, the reference root — now has a defined notion of "where" to bind to.

**Negative — and accepted.**

- Environment roots carry the resolution logic and are therefore more verbose than a one-call landing-zone module would be. We accept this: ADR 0004 already chose legibility over orchestration, and the verbosity is the adopter's real topology made explicit.
- Binding by role assumes a *conformant-enough* ALZ. An adopter with a wildly non-standard hierarchy must map their tree onto the four roles themselves. We accept this as the cost of not owning their hierarchy; the role set is small enough to map.
- The vocabulary is a contract to maintain as new scope-needing modules appear. We accept it: it is small, additive, and far cheaper than every module reinventing a scope stopgap.

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — the binding is code in the environment root, not portal-applied scope.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — MG-default-with-RG-pilot keeps assignment scoped and evidence-based, not a blanket ban.
- [ADR 0001](./0001-iac-terraform-with-avm.md) — the estate is Terraform on AVM; scopes are inputs to that, not a new tool.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — modules ship initiatives; this ADR says where they assign.
- [ADR 0004](./0004-composition-by-output-data.md) — no `landing-zone` orchestrator; the binding is consumer-boundary data.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — the assignment-scope decision ADR 0008 §5 deferred to "the landing-zone decision."
- [ADR 0010](./0010-tag-taxonomy.md) — the tag initiative is one of the estate-wide assignments that binds at MG scope.
