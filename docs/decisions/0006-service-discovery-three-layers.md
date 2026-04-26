---
id: 6
title: Service discovery as three concerns with three tools
status: accepted
date: 2026-04-26
categories: [networking, integration]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-003, AP-009]
cites_adrs: [ADR-0005, ADR-0007]
---

# ADR 0006 — Service discovery as three concerns with three tools

## Context

"Service discovery" is one phrase that hides three distinct concerns:

- **Runtime resolution.** At call time, how does service A find an endpoint for service B?
- **Cross-boundary contract.** When traffic crosses a trust or environment boundary (cluster → cluster, Azure → another cloud, team → team), how is the contract registered, governed, and observable?
- **Inventory and ownership.** Who owns this service? Where are its docs? What does it depend on?

The anti-pattern of conflating these into a single mechanism — typically, hand-edited DNS in env vars ([AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints)) — produces hard-coded topologies that ossify. Modern Azure has a different right-tool answer for each concern.

A particularly relevant case: this estate integrates with a SaaS digital banking platform hosted on a different cloud (AWS). That cross-cloud, cross-trust integration belongs squarely in the cross-boundary-contract layer, not the runtime layer.

## Decision

Three distinct mechanisms, each owning one concern.

### Runtime resolution (in-cluster)

**Kubernetes DNS plus the AKS Istio-based service mesh add-on (managed Istio).** Pods address services by Kubernetes name; the mesh layers in mTLS, retry policy, traffic shifting, and golden-signal telemetry. No additional service-registry product (Consul, Eureka) is needed inside a cluster. Cross-cluster intra-Azure traffic is mediated by the mesh's east-west gateway when needed.

### Cross-boundary contract

**Azure API Management (APIM).** Every externally-callable API is published in APIM with:

- An OpenAPI definition stored next to the service.
- Throttling, rate-limit, and quota policies appropriate to the consumer.
- mTLS or token-based authentication via Entra ID.
- Observability hooks emitting to the substrate ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)).
- A stable URL that survives backend movement.

APIM is the registry by virtue of being the only way in. Cross-cloud integrations call our APIM, not the upstream vendor directly. For the SaaS digital banking integration specifically, this means **we publish a facade API in our APIM that fronts the upstream vendor**. The facade gives us a circuit breaker, retry budget, the substrate's observability story, and a single chokepoint when the upstream has an incident — properties that are not negotiable for a tier-0 dependency.

### Inventory and ownership

**Backstage.** The developer portal hosts:

- The service catalog with owner, lifecycle stage, and technology metadata.
- The dependency graph, derived from APIM definitions and Terraform module references.
- TechDocs, which pulls markdown directly from this repo (not a forked copy).
- Runbook links pointing to the `monitoring/` bundle of the relevant module.

Backstage is not in the runtime call path; it is the human-facing inventory. It can be temporarily wrong without causing outages. ([AP-009](../anti-patterns.md#ap-009--doc-rot) is what happens when inventory and runtime are conflated and the inventory rots.)

### Wiring (orthogonal but related)

Connection wiring uses **managed identity plus Azure Service Connector**. Endpoint and credential injection happens at deploy time via identity-based connections, not by editing env vars at runtime. This is the necessary complement to the three layers above — without it, hand-rolled env-var plumbing reappears at the wiring layer.

## Consequences

**Positive.**

- Runtime topology is portable; service B can move clusters or regions without consumer redeploys.
- Cross-boundary calls have one chokepoint with circuit-breaking, observability, and policy. The SaaS-banking integration becomes operationally tractable.
- Inventory is queryable; new services have a front door.
- No DNS-in-env-vars; rotation and reconnection are managed-identity problems, not human problems.
- Each tool fits its concern; we don't pay the complexity of a hand-rolled cross-cloud registry.

**Negative — and accepted.**

- Three tools is more surface than one bespoke registry. We accept the surface in exchange for the right-tool fit.
- APIM in the request path adds latency. We accept it for cross-boundary calls; intra-cluster calls go mesh-direct.
- Backstage is a developer-experience tool, not a runtime SLA-bearing service. We accept that the catalog can be temporarily wrong without runtime impact.
- AKS service-mesh add-on is a managed service with its own cadence; we follow Microsoft's release cycle for upgrades.

## Cites

- [AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints) — what this ADR prevents.
- [AP-009](../anti-patterns.md#ap-009--doc-rot) — context for keeping inventory in Backstage with TechDocs pulled from repo.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — APIM emits to the substrate.
- [ADR 0007](./0007-change-as-code.md) — manages the deviation case where a service is *not* in APIM.
