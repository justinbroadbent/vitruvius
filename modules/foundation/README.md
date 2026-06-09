# modules/foundation/

The foundation layer. Modules that everything else depends on or composes against. Each is opinionated cross-cutting per [`docs/golden-paths.md`](../../docs/golden-paths.md) and follows the contract in [ADR 0011](../../docs/decisions/0011-module-manifest.md).

## v0.1.0 modules

| Module | Status | What it does |
|---|---|---|
| [`naming/`](./naming/) | experimental | Pure-logic. Produces canonical Azure resource names from a small set of inputs. No resources created. |
| [`tags/`](./tags/) | experimental | Authority on the tag taxonomy ([ADR 0010](../../docs/decisions/0010-tag-taxonomy.md)). Produces a tag map and ships the policy initiative that enforces the taxonomy. |
| [`diagnostic-settings/`](./diagnostic-settings/) | experimental | Substrate-routing safety net. Ships the policy initiative that ensures common Azure resources route diagnostic settings to the platform Log Analytics workspace ([ADR 0005](../../docs/decisions/0005-observability-substrate-and-signal-parity.md)). |
| [`identity/`](./identity/) | experimental | Platform-baseline user-assigned managed identities. Identity primitives only — no role assignments, no custom roles, no federation; deliberately minimal pending real RBAC strategy decisions. |

## What goes in foundation vs other areas

Foundation is for primitives that:

- Are consumed by many other modules (naming, tags) or by the policy substrate (diagnostic-settings, identity).
- Have no upstream module dependencies (per [ADR 0004](../../docs/decisions/0004-composition-by-output-data.md), no module imports another).
- Are platform-singleton — one canonical implementation, not a per-workload variant.

Things that are **not** foundation:

- Networking primitives — `modules/networking/` (deferred).
- Shared platform services like the LAW itself, central secret stores, the container registry — `modules/platform-services/` (the observability substrate ships; the rest is deferred).
- Workload shapes — `modules/workload-patterns/`.
