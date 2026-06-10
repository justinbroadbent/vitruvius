# modules/networking/

Planned home for networking primitives — hub topology, spoke patterns, private-endpoint conventions, NSG baselines, VNet peering, and DNS-zone wiring.

**Status: the decided core ships; egress enforcement is deferred.** [`hub/`](./hub/) provides the hub VNet, centralized private DNS zones, and the AMPLS (the substrate's private-link prerequisite). The firewall — product, SKU, and rule shape — remains v0.2, because choosing it before a real estate's egress requirements exist would be a decision made blind and reversed later (issue #9).

The first networking module is likely `hub` — the platform's central VNet with shared services (Azure Firewall or NVA, private-DNS zones for private-endpoint resolution, the bastion subnet, and the spoke-peering surface). The shape is opinionated cross-cutting per [`docs/golden-paths.md`](../../docs/golden-paths.md): consumers compose hub outputs into spoke configs at the consumer boundary, not via module imports ([ADR 0004](../../docs/decisions/0004-composition-by-output-data.md)).

Networking decisions are typically environment-specific (region pair, address-space allocation, peering topology). Per-environment configuration lives in environment root configs; this directory contains the **modules** those configs compose.

Until a module exists, workload patterns assume their consumer has handled networking — `web-api-aks` accepts `aks_oidc_issuer_url` as input rather than provisioning the cluster, for example.
