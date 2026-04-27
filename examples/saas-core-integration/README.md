# examples/saas-core-integration

The cross-cloud integration story: an AWS-hosted SaaS core ↔ Azure platform. This is the shape the platform takes to integrate with a vendor-hosted core (e.g., a digital banking core running on AWS) without losing the platform's observability, identity, and policy posture on the Azure side.

**Status: deferred. Information-gathering blocking the build.**

What this example will eventually demonstrate:

- An APIM-fronted facade on the Azure side that mediates traffic to the SaaS core's API.
- Outbound network egress through controlled paths (specific NAT IPs whitelisted with the vendor; egress logged to the substrate).
- Identity federation patterns — the Azure-side workloads call the SaaS core; how that authentication flows.
- Observability of the integration boundary — substrate captures the Azure side; the vendor's telemetry stays vendor-side; reconciliation is documented.
- Member-data handling at the integration boundary — what crosses, what doesn't, and the data-classification implications per [ADR 0010](../../docs/decisions/0010-tag-taxonomy.md).

What's blocking:

- The vendor's API contract isn't yet collected. Documenting a generic pattern without a real contract risks describing something that doesn't match the vendor's actual surface.
- The egress allowlist requirements (vendor-side) and the platform's outbound NAT topology need real numbers, not placeholders.
- The data-classification decision for traffic crossing the boundary is a security/compliance conversation that hasn't happened.

When the build starts, the example composes existing foundation modules (`naming`, `tags`, `identity`) with `workload-patterns/web-api-aks` (or `apim-bff` once that pattern exists). It does **not** check in the vendor's proprietary contract or SDK — only the integration **pattern** per [`AGENTS.md`](../../AGENTS.md) hard rule 6.
