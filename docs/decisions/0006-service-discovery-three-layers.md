---
id: 6
title: Service discovery as three concerns with three tools
status: accepted
date: 2026-04-26
categories: [networking, integration]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-003, AP-009]
cites_adrs: [ADR-0005, ADR-0007, ADR-0012]
---

# ADR 0006 — Service discovery as three concerns with three tools

## Context

"Service discovery" sounds like one question but hides three distinct concerns:

- **Runtime resolution.** At the moment of a call, how does service A find a live address (an **endpoint**) for service B?
- **Cross-boundary contract.** When traffic crosses a trust or environment boundary (cluster → cluster, Azure → another cloud, team → team), how is that connection registered, governed, and watched?
- **Inventory and ownership.** For the humans: who owns this service? Where are its docs? What does it depend on?

Cramming all three into a single mechanism — typically service addresses hand-typed into configuration files ([AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints)) — produces a hard-coded layout that ossifies: nothing can move without editing every caller. Modern Azure has a different right-tool answer for each concern.

A particularly relevant case: this estate integrates with a vendor-hosted **SaaS** digital banking platform (software the vendor runs for us) on another cloud. That cross-cloud, cross-trust integration belongs squarely in the cross-boundary-contract layer, not the runtime layer.

## Decision

Three distinct mechanisms, each owning one concern.

### Runtime resolution (in-cluster)

**Kubernetes DNS plus the AKS Istio-based service mesh add-on (managed Istio).** Kubernetes — the system that runs our containerized applications; AKS is Azure's managed version — has address lookup built in: a pod (one running unit of an application) reaches a service by its Kubernetes name. The **service mesh** add-on layer handles the rest automatically: **mTLS** (mutual TLS — both sides of a call prove their identity and the traffic is encrypted), retry policy, traffic shifting, and golden-signal telemetry (the standard per-call health measurements). No additional service-registry product (Consul, Eureka) is needed inside a cluster. When traffic must cross between clusters but stay inside Azure, the mesh's east-west gateway mediates it.

### Cross-boundary contract

**Azure API Management (APIM)** — Azure's "front door" product for publishing APIs. Every externally-callable API is published in APIM with:

- An OpenAPI definition (a machine-readable description of the API) stored next to the service.
- Throttling, rate-limit, and quota policies appropriate to the consumer.
- mTLS or token-based authentication via Entra ID (Azure's identity service).
- Observability hooks emitting to the substrate — our central monitoring pipeline ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)).
- A stable URL that survives backend movement: the service behind it can move without callers noticing.

APIM is the registry by virtue of being the only way in. Cross-cloud integrations call our APIM, not the upstream vendor directly. For the SaaS digital banking integration specifically, this means **we publish a facade API in our APIM that fronts the upstream vendor** — a protective wrapper in front of their system. The facade gives us a **circuit breaker** (a switch that stops hammering a dependency that is already failing), a retry budget, the substrate's observability story, and a single chokepoint when the upstream has an incident. For a **tier-0** dependency (highest criticality — the business stops without it), those properties are not negotiable.

### Inventory and ownership

**Backstage** — a developer portal: a searchable internal website that catalogs our services. It hosts:

- The service catalog with owner, lifecycle stage, and technology metadata.
- The dependency graph, derived from APIM definitions and Terraform module references.
- TechDocs, which pulls markdown directly from this repo (not a forked copy that could drift).
- Runbook links pointing to the `monitoring/` bundle of the relevant module.

Backstage is deliberately not in the runtime call path; it is the human-facing inventory. It can be temporarily wrong without causing outages. ([AP-009](../anti-patterns.md#ap-009--doc-rot) is what happens when inventory and runtime are conflated and the inventory rots.)

### Wiring (orthogonal but related)

Connection wiring — how a deployed service actually receives the addresses and credentials it needs — uses **managed identity** (Azure gives the service its own built-in identity; no password involved) **plus Azure Service Connector**. Endpoints and credentials are injected at deploy time via identity-based connections, not by editing environment variables at runtime. This is the necessary complement to the three layers above — without it, hand-rolled env-var plumbing reappears at the wiring layer.

> **In plain terms:** "how do services find each other?" is like "how do I reach a company?" — the internal phone extension (runtime resolution), the official public number with a receptionist (the APIM front door), and the staff directory (Backstage) are different needs, served by different tools.

## What this does not decide

- **APIM tier/topology, the mesh upgrade cadence, and the Backstage instance** — concrete sizing and operational specifics are deferred (Backstage's build is gated entirely — see the catalog-contract ADR).
- **The SaaS-banking facade contract** — the upstream vendor's API surface isn't collected yet; the facade *pattern* is decided, the specifics are blocked (`examples/saas-core-integration`).
- **The three tools as products** — that runtime resolution is the mesh, cross-boundary is APIM, and inventory is Backstage *is* the decision; swapping any one implementation is left open per the reversibility note.

## Reversibility

The three concerns also have three different reversibility profiles — which is itself a reason to keep them separate:

- **Inventory (Backstage): cheap to change (two-way door).** It is out of the runtime path and "can be temporarily wrong without causing outages." Swapping or even removing it touches no live traffic.
- **Runtime resolution (managed Istio): moderately reversible.** It is the AKS add-on; changing service mesh is a per-cluster migration, not estate-wide by design.
- **Cross-boundary contract (APIM): load-bearing (one-way door).** Once consumers — including the cross-cloud callers — depend on stable APIM URLs and the tier-0 facade is the chokepoint, moving off it means a coordinated migration across every published contract. This is the layer to commit to most carefully.

## Consequences

**Positive.**

- Runtime topology is portable: service B can move clusters or regions without its consumers redeploying.
- Cross-boundary calls have one chokepoint with circuit-breaking, observability, and policy. The SaaS-banking integration becomes something we can actually operate and watch.
- The inventory is queryable; new services have a front door.
- No addresses typed into environment variables; rotation and reconnection are managed-identity problems, not human problems.
- Each tool fits its concern; we don't pay the complexity of a hand-rolled cross-cloud registry.

**Negative — and accepted.**

- Three tools is more surface to run than one bespoke registry. We accept the surface in exchange for the right-tool fit.
- APIM sits in the request path and adds latency. We accept it for cross-boundary calls; intra-cluster calls go mesh-direct and skip it.
- Backstage is a developer-experience tool, not a runtime SLA-bearing service — no uptime promise rides on it. We accept that the catalog can be temporarily wrong without runtime impact.
- The AKS service-mesh add-on is a managed service with its own cadence; we follow Microsoft's release cycle for upgrades.

## Cites

- [AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints) — what this ADR prevents.
- [AP-009](../anti-patterns.md#ap-009--doc-rot) — context for keeping inventory in Backstage with TechDocs pulled from the repo.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — APIM emits to the substrate.
- [ADR 0012](./0012-collaborative-design.md) and the deviation workflow in [docs/golden-paths.md](../golden-paths.md) — govern the deviation case where a service is *not* in APIM.
