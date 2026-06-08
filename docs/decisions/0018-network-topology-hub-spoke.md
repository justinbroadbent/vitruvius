---
id: 18
title: Network topology is hub-spoke with default-deny egress and centralized private DNS
status: accepted
date: 2026-06-08
categories: [networking, foundation, security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-003, AP-005, AP-004]
cites_adrs: [ADR-0004, ADR-0006, ADR-0008, ADR-0017, ADR-0024]
---

# ADR 0018 — Network topology is hub-spoke with default-deny egress and centralized private DNS

## Context

[ADR 0006](./0006-service-discovery-three-layers.md) decided service *discovery* — runtime resolution (mesh), cross-boundary contract (APIM), inventory (Backstage). None of it decides the **L3 topology** those layers sit on. `networking/` is one of the four areas with zero implementation, and its README says the first module is `hub` — but the hub cannot be built without this decision: it needs an address plan, a peering model, a DNS strategy, and an egress posture.

The forces:

- **Regulated-FS egress control.** A credit union must be able to tell an examiner where data can leave the network. "Any workload can reach any internet endpoint" is not an answer; known, audited egress points are.
- **Private-by-default already assumed.** [ADR 0017](./0017-terraform-state-and-backend.md) puts state behind a private endpoint; [ADR 0009](./0009-secrets-ephemeral-by-default.md) does the same for Key Vault. Private endpoints are useless without a private-DNS resolution strategy — which nothing has decided.
- **A cross-cloud neighbor.** The estate integrates with an AWS-hosted SaaS banking core (ADR 0006). Address space must not overlap with that side, or with on-prem.
- **Reference, not blueprint.** The adopter already has a tenant, very likely an ALZ connectivity subscription, and real CIDRs. We must decide the *shape* and bind to ADR 0024's scopes, and defer the numbers.

## Decision

### 1. Hub-spoke, aligned to CAF/ALZ; the hub is platform-owned

A central **hub VNet per region** holds shared connectivity services (egress firewall, private-DNS resolution, hybrid-connectivity gateways, Bastion). **Workload spokes** peer to the hub. The hub lives in the ALZ **platform/connectivity subscription**; spokes live in the **environment-subscriptions** ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) §3). Traditional VNet hub-spoke is the reference default; **Azure Virtual WAN is a supported adopter variant** for estates that outgrow self-managed peering — the contract below (chokepoint egress, central DNS, non-overlap) holds for either.

### 2. Spokes never peer to each other; cross-spoke traffic transits the hub

Peering is hub↔spoke only. There is **no spoke-to-spoke peering**; east-west traffic that must cross spokes routes through the hub so it can be inspected and policy-controlled. The hub is the deliberate chokepoint — the property that makes egress control (§4) and segmentation enforceable.

### 3. Address space is centrally allocated, non-overlapping, and documented — numbers deferred

The **discipline** is decided; the prefixes are not. Address space is allocated centrally (never ad hoc per team), is **non-overlapping** across environments, regions, on-prem, and the AWS SaaS side, and the allocation is documented as code in the environment roots. The reference scheme is a per-environment-per-region supernet carved into spoke subnets; the concrete base prefixes, VNet/subnet sizes, and region pairs are **adopter/environment-root data** (the networking README already places per-environment config there). Re-IPing a live estate is the expensive migration this discipline exists to prevent.

### 4. Egress is default-deny through the hub firewall; egress points are known and audited

All spoke egress (`0.0.0.0/0`) routes via UDR to the hub's **Azure Firewall** (the reference default; an NVA is the adopter alternative). The firewall enforces **FQDN-allowlist egress**; there is **no direct internet egress from spokes**. Egress is a small, named, audited set, not "anywhere" — the regulated-FS data-exfiltration posture. The allowlist is built per workload and follows the [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) audit-before-deny lifecycle (observe real egress in `Audit`, then enforce), so default-deny does not become an [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) blanket ban that breaks legitimate traffic.

### 5. Private DNS is centralized in the platform and auto-registered

The `privatelink.*` private-DNS zones (e.g. `privatelink.blob.core.windows.net` for ADR 0017 state, `privatelink.vaultcore.azure.net` for ADR 0009 Key Vault) are **platform-owned**, defined once, and linked to the spokes and the hub resolver. Private-endpoint A-records register into these central zones automatically via an Azure Policy `DeployIfNotExists` initiative ([ADR 0003](./0003-modules-ship-policy-and-monitoring.md) / [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md)), not by hand. Resolution is served from the hub (Azure DNS Private Resolver), so on-prem and cross-cloud callers resolve the same names.

### 6. Composition is by output data — no networking orchestrator

Per [ADR 0004](./0004-composition-by-output-data.md), the `hub` module produces outputs — hub VNet ID, firewall private IP (the UDR next-hop), private-DNS zone IDs, route-table IDs — and spoke/workload roots **consume those outputs at the environment-root boundary**. There is no `networking` orchestrator module that wires hub to spokes; the consumer does it. Workload patterns (e.g. `web-api-aks`) accept the relevant outputs as inputs, exactly as they already accept `aks_oidc_issuer_url` rather than provisioning networking themselves.

## What this does not decide

- **Concrete CIDRs, base prefixes, VNet/subnet sizing, regions, and region pairs** — adopter/environment-root data (§3).
- **Azure Firewall vs NVA, and the Firewall SKU / policy specifics** — adopter choice; Azure Firewall is the reference default (§4).
- **Traditional hub-spoke vs Azure Virtual WAN** — VNet hub-spoke is the reference default; vWAN is a supported variant for scale (§1). The choice is the adopter's connectivity decision.
- **The concrete egress FQDN allowlist** — workload-specific; ships with workload patterns and follows the ADR 0008 lifecycle (§4).
- **Hybrid connectivity (ExpressRoute / VPN) and the DNS Private Resolver forwarding rulesets to on-prem** — depends on the adopter's existing estate; the hub *hosts* these, the specifics are deferred.
- **Intra-spoke micro-segmentation / NSG rule sets and DDoS tier** — workload-pattern and per-environment concerns, not the topology contract.
- **IPv6** — out of scope unless an adopter ADR adds it.

## Reversibility

**Load-bearing, with the address plan as the true one-way door — so it is the thing we get right first.** The hub-spoke *shape* is reversible only by coordinated migration once workloads are peered and addressed; the **non-overlapping address allocation** (§3) is the most expensive to unwind, because re-IPing a live estate touches every spoke, peering, route, and firewall rule — which is exactly why the discipline (central, non-overlapping, documented) is committed from day one while the numbers stay deferred to adopters. The **default-deny egress chokepoint** (§4) is likewise cheap to hold from the start and painful to retrofit (adding a chokepoint after workloads run breaks live egress), so it is a day-one posture. By contrast, the genuinely two-way choices are parameterized out: firewall-vs-NVA and the egress allowlist are config; hub-spoke-vs-vWAN is an adopter swap the contract survives; central DNS zones are additive. What would have to change to undo the load-bearing parts: a re-addressing project and a re-peering — which no config flag can make cheap, the reason the shape is decided before the first spoke exists.

## Consequences

**Positive.**

- The `hub` module (roadmap #9) finally has the address plan, peering model, DNS strategy, and egress posture it needs to be built.
- Egress is a known, audited, default-deny set through one chokepoint — a direct answer to the examiner's "where can data leave?" (§4).
- Private endpoints assumed by ADR 0017 and ADR 0009 actually resolve, via central auto-registered DNS (§5).
- Topology stays portable under ADR 0006's discovery layers: services move spokes/regions without consumer redeploys (complements [AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints)).
- No networking orchestrator; the estate's wiring is legible at the environment-root boundary (ADR 0004), and address allocation is documented as code (AP-004).

**Negative — and accepted.**

- A hub chokepoint adds a hop and a shared dependency every spoke relies on. We accept it: the chokepoint *is* the control point egress and segmentation require; the hub is built for HA accordingly.
- Default-deny egress means new external dependencies need an allowlist change. We accept the friction and soften it with the ADR 0008 audit-then-enforce lifecycle, so it informs rather than blocks.
- Central address allocation is more coordination than letting teams pick CIDRs. We accept it: the alternative is overlap and the re-IP migration §3 exists to avoid.
- Self-managed hub-spoke is more moving parts than Virtual WAN. We accept it for the reference default and name vWAN as the adopter off-ramp at scale.

## Cites

- [AP-003](../anti-patterns.md#ap-003--hard-coded-service-endpoints) — portable topology under ADR 0006's discovery layers; no hard-coded paths.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — default-deny egress via the ADR 0008 lifecycle, not a blanket ban.
- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — address allocation and routing are documented as code.
- [ADR 0004](./0004-composition-by-output-data.md) — hub outputs are consumed by spokes at the consumer boundary; no orchestrator.
- [ADR 0006](./0006-service-discovery-three-layers.md) — this is the L3 topology beneath the three discovery layers.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — egress allowlist and private-DNS auto-registration follow the policy lifecycle.
- [ADR 0017](./0017-terraform-state-and-backend.md) — state's private endpoint needs the central privatelink DNS this ADR defines.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — hub in the platform subscription, spokes in environment-subscriptions.
