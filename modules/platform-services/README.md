# modules/platform-services/

Planned home for shared platform services that workload patterns and foundation modules consume — the observability substrate, central secret stores, the container registry, and similar platform-singletons.

**Status: building out.** First module shipped.

| Module | What it does |
|---|---|
| [`observability-substrate`](./observability-substrate/) | The Log Analytics workspace + workspace-based Application Insights + alert-routing that several modules already consume as `log_analytics_workspace_id` (in `web-api-aks` and `foundation/diagnostic-settings`). Implements the substrate side of [ADR 0005](../../docs/decisions/0005-observability-substrate-and-signal-parity.md). The OTel collector deployment is host-dependent and tracked separately. |

Other v0.2+ candidates:

- `secrets` — central Key Vault + rotation tooling (interacts with [ADR 0009](../../docs/decisions/0009-secrets-ephemeral-by-default.md)).
- `container-registry` — shared ACR with the geo-replication and content-trust posture.

Each module follows the same shape as the existing foundation modules: `manifest.yaml`, policy and monitoring artifacts per [ADR 0003](../../docs/decisions/0003-modules-ship-policy-and-monitoring.md) (inline Terraform or `policy/`/`monitoring/` JSON), examples, tests, and AGENTS.md guidance.
