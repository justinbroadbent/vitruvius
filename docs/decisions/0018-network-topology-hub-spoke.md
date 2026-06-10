---
id: 18
title: Network topology is hub-spoke with default-deny egress and centralized private DNS
status: accepted
date: 2026-06-08
categories: [networking, foundation, security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-003, AP-005, AP-004]
cites_adrs: [ADR-0003, ADR-0004, ADR-0006, ADR-0008, ADR-0009, ADR-0017, ADR-0024]
---

# ADR 0018 — Network topology is hub-spoke with default-deny egress and centralized private DNS

## Context

[ADR 0006](./0006-service-discovery-three-layers.md) decides service *discovery* — how services find each other at runtime, how cross-boundary calls are governed, and how humans find what exists. This ADR decides the **network topology** those layers sit on: the L3 layout — the IP addressing and routing layer — of the estate's networks. The forces:

- **Regulated-FS egress control.** **Egress** is traffic leaving the network. A credit union must be able to say where data can leave; known, audited egress points are the answer, and unrestricted internet egress is not.
- **Private-by-default.** Terraform state ([ADR 0017](./0017-terraform-state-and-backend.md)) and Key Vault ([ADR 0009](./0009-secrets-ephemeral-by-default.md)) sit behind **private endpoints** — private network addresses instead of internet-facing ones — and private endpoints only work with a strategy for **private DNS**, the name-lookup service that resolves those private addresses.
- **A cross-cloud neighbor.** The estate integrates with a vendor-hosted SaaS banking core on another cloud ([ADR 0006](./0006-service-discovery-three-layers.md)); our address space must not overlap with it or with on-prem networks.
- **Reference, not blueprint.** The adopter has a tenant, an ALZ connectivity subscription, and real CIDRs (a **CIDR** is a block of IP addresses, written like `10.0.0.0/16`). This ADR decides the shape and binds to ADR 0024's scopes; the numbers are the adopter's.

## Decision

### 1. Hub-spoke, aligned to CAF/ALZ; the hub is platform-owned

**Hub-spoke** is the wheel-shaped layout: one central network holds the shared plumbing, and each workload gets its own network connected to it. Concretely, a central hub **VNet** (an Azure virtual network) per region holds the shared connectivity services — the egress firewall, private-DNS resolution, gateways for hybrid connectivity to on-prem, and Bastion (Azure's managed jump-box for administrative access). Workload spokes **peer** to the hub (peering is the link that connects two VNets). The hub lives in the ALZ platform/connectivity subscription; spokes live in the environment-subscriptions ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)). Traditional VNet hub-spoke is the reference default; Azure Virtual WAN (Microsoft's managed version of the same shape) is a supported variant for estates that outgrow self-managed peering — the contract below holds for either.

### 2. Spokes never peer to each other; cross-spoke traffic transits the hub

Peering is hub↔spoke only. **East-west traffic** — traffic between workloads, as opposed to traffic entering or leaving the estate — that must cross spokes routes through the hub, where it can be inspected and policy-controlled. The hub is the chokepoint that makes egress control (§4) and segmentation enforceable.

> **In plain terms:** the network is shaped like an airport. Every workload (spoke) connects only to the central terminal (the hub), and everything leaving the estate passes through one guarded exit with a known list of allowed destinations.

### 3. Address space is centrally allocated, non-overlapping, and documented

The platform allocates address space centrally, keeps it non-overlapping across environments, regions, on-prem, and the other cloud's SaaS core, and documents it as code in the environment roots. The reference scheme is one large block (a **supernet**) per environment per region, carved into spoke subnets; the concrete base prefixes, VNet/subnet sizes, and region pairs are adopter data.

### 4. Egress is default-deny through the hub firewall; egress points are known and audited

All spoke egress (`0.0.0.0/0` — i.e., everything outbound) routes via **UDR** (a user-defined route — a routing rule that overrides Azure's defaults) to the hub's Azure Firewall (the reference default; a third-party network virtual appliance, an **NVA**, is the adopter alternative). The firewall enforces an **FQDN allowlist**: only traffic to explicitly listed domain names gets out. Spokes have no direct internet egress. The allowlist is built per workload and follows the [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) audit-before-deny lifecycle, so default-deny does not become an [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) blanket ban.

### 5. Private DNS is centralized in the platform and auto-registered

The `privatelink.*` private-DNS zones — the lookup zones that resolve Azure services to their private addresses — are platform-owned, defined once, and linked to the spokes and the hub resolver. When a private endpoint is created, its DNS record (its A-record) registers into these central zones automatically, via an Azure Policy `DeployIfNotExists` initiative ([ADR 0003](./0003-modules-ship-policy-and-monitoring.md), [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md)). Resolution is served from the hub (Azure DNS Private Resolver), so on-prem and cross-cloud callers resolve the same names as everything inside.

### 6. Composition is by output data — no networking orchestrator

Per [ADR 0004](./0004-composition-by-output-data.md), the `hub` module exposes outputs — hub VNet ID, private-DNS zone IDs, subnet IDs, the AMPLS ID — and spoke/workload roots consume them at the environment-root boundary. The shipped `networking/hub` v0.1 satisfies the non-firewall half of this contract; the firewall surface (firewall private IP, route-table IDs) ships with the v0.2 egress work (issue #9). There is no orchestrator module wiring hub to spokes; the consumer does the wiring. Workload patterns accept the relevant outputs as inputs.

## What this does not decide

- **Concrete CIDRs, base prefixes, VNet/subnet sizing, regions, and region pairs** — adopter data (§3).
- **Azure Firewall vs NVA, and the firewall SKU / policy specifics** — adopter choice; Azure Firewall is the reference default (§4).
- **Traditional hub-spoke vs Azure Virtual WAN** — VNet hub-spoke is the reference default; vWAN is a supported variant for scale (§1).
- **The concrete egress FQDN allowlist** — workload-specific; follows the ADR 0008 lifecycle (§4).
- **Hybrid connectivity (ExpressRoute / VPN) and DNS forwarding rulesets to on-prem** — adopter estate; the hub hosts these.
- **Intra-spoke micro-segmentation / NSG rule sets and the DDoS tier** — workload-pattern and per-environment concerns.
- **IPv6** — out of scope unless an adopter ADR adds it.

## Reversibility

The hub-spoke shape and the address plan are load-bearing; the choices around them are not. Non-overlapping address allocation (§3) is the most expensive thing to unwind — re-numbering a live estate touches every spoke, peering, route, and firewall rule — so the discipline is held from day one even while the actual numbers stay deferred. Default-deny egress (§4) is cheap to hold from the start and painful to retrofit, so it is a day-one posture. Firewall-vs-NVA and the egress allowlist are configuration; hub-spoke-vs-vWAN is an adopter swap the contract survives; central DNS zones are additive.

## Consequences

**Positive.**

- Egress is a known, audited, default-deny set through one chokepoint — a clear answer to where data can leave (§4).
- The private endpoints assumed by ADR 0017 and ADR 0009 actually resolve, via central auto-registered DNS (§5).
- Topology stays portable under ADR 0006's discovery layers: services can move spokes or regions without their consumers redeploying ([AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints)).
- No networking orchestrator: the estate's wiring is legible at the environment-root boundary (ADR 0004), and address allocation is documented as code (AP-004).

**Negative — and accepted.**

- A hub chokepoint adds a network hop and a shared dependency every spoke relies on. The chokepoint is the control point that egress and segmentation require; the hub is built for high availability accordingly.
- Default-deny egress means every new external dependency needs an allowlist change. The ADR 0008 audit-then-enforce lifecycle softens this.
- Central address allocation is more coordination than letting teams pick their own CIDRs. The alternative is overlap and the re-numbering migration §3 avoids.
- Self-managed hub-spoke is more moving parts than Virtual WAN, which is named as the adopter off-ramp at scale.

## Cites

- [AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints) — portable topology under ADR 0006's discovery layers.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — default-deny egress via the ADR 0008 lifecycle, not a blanket ban.
- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — address allocation and routing documented as code.
- [ADR 0004](./0004-composition-by-output-data.md) — hub outputs consumed by spokes at the consumer boundary.
- [ADR 0006](./0006-service-discovery-three-layers.md) — the L3 topology beneath the three discovery layers.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — egress allowlist and private-DNS auto-registration follow the policy lifecycle.
- [ADR 0017](./0017-terraform-state-and-backend.md) — state's private endpoint uses the central privatelink DNS.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — hub in the platform subscription, spokes in environment-subscriptions.
