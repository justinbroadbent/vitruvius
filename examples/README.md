# examples/

Reference compositions — foundation and workload-pattern modules wired together into realistic scenarios. Examples are **not modules**; they don't ship policy or get tested in CI like modules do. They exist to demonstrate composition and to be copied as starting points.

**Status: deferred.** No examples ship yet. Two are planned:

- [`saas-core-integration/`](./saas-core-integration/) — AWS-hosted SaaS core ↔ Azure platform integration. The Lumin Digital cross-cloud story.
- [`legacy-replatform/`](./legacy-replatform/) — vendor BPM and data platforms migrated to Azure-native equivalents.

Each example will eventually contain:

- A `README.md` with the scenario, the architectural narrative, and the sequence of module compositions.
- A working root-level Terraform configuration that an operator can adapt to their subscription.
- Diagrams of the resulting topology.

For now, the per-example READMEs document the planned scope and what's blocking the build (typically: real information about the target integration that hasn't been collected yet).
