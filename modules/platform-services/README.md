# modules/platform-services/

Planned home for shared platform services that workload patterns and foundation modules consume — the observability substrate, central secret stores, the container registry, and similar platform-singletons.

**Status: deferred to v0.2.** No modules ship yet.

The first platform-services module is likely `observability-substrate` — the Log Analytics workspace, Application Insights instances, action groups, and the alert-routing infrastructure that several modules already treat as external inputs (`log_analytics_workspace_id` in `web-api-aks` and `foundation/diagnostic-settings`). Building it closes the loop on [ADR 0005](../../docs/decisions/0005-observability-substrate-and-signal-parity.md).

Other v0.2+ candidates:

- `secrets` — central Key Vault + rotation tooling (interacts with [ADR 0009](../../docs/decisions/0009-secrets-ephemeral-by-default.md)).
- `container-registry` — shared ACR with the geo-replication and content-trust posture.

Each module follows the same shape as the existing foundation modules: `manifest.yaml`, `policy/`, `monitoring/`, examples, tests, and AGENTS.md guidance.
