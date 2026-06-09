# modules/workload-patterns/

Workload patterns — opinionated module shapes for common application archetypes. Each pattern wires the **Azure-side** primitives a workload of that shape needs (identity, secrets, observability, policy) so app teams can focus on the application itself.

## v0.1.0 patterns

| Pattern | Status | What it provisions |
|---|---|---|
| [`web-api-aks/`](./web-api-aks/) | experimental | Containerized HTTP API on AKS. UAI + workload-identity federation, Key Vault via AVM, KV-hardening policy initiative, KV diagnostic settings. App-team owns the Kubernetes resources. |

## Planned

- `function-event-driven/` — Azure Functions for event-driven workloads (Service Bus, Event Grid, blob triggers). Different identity story (Function App's system-assigned identity), different observability footprint (Application Insights as the primary signal source).
- `data-pipeline/` — managed batch / streaming workloads (Data Factory, Synapse, or Databricks). Different cross-cutting concerns (data-classification-driven CMK, lineage tracking).
- `apim-bff/` — APIM as a backend-for-frontend / cross-network mediation pattern, including the cross-cloud SaaS-core integration shape.

Each new pattern follows the same shape as `web-api-aks`: `manifest.yaml`, policy and monitoring artifacts per [ADR 0003](../../docs/decisions/0003-modules-ship-policy-and-monitoring.md), examples, tests, and AGENTS.md guidance documenting the cross-cutting choices and what the app-team owns.

## Workload patterns multiply slowly

Three or four total is plausible; ten is not. Each pattern is a real architectural decision about how a class of workload runs on this platform — not a configuration variant. If a request looks like "add a flag for X" rather than "this is a different shape," extend the existing pattern instead of creating a new one. See [`web-api-aks/AGENTS.md`](./web-api-aks/AGENTS.md) § "When to add a new workload pattern" for the test.
