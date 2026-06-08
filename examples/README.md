# examples/

Reference compositions — foundation and workload-pattern modules wired together into realistic scenarios. Examples are **not modules**; they don't ship policy or `terraform test` suites. CI validates them (`init` + `validate`). They exist to demonstrate composition and to be copied as starting points.

## Shipping

- [`reference-landingzone/`](./reference-landingzone/) — a platform landing zone composed from the foundation and platform-services modules. The worked demonstration of composition by output data ([ADR 0004](../docs/decisions/0004-composition-by-output-data.md)).

## Planned

Both are blocked on real information about the target integration, not on the repo:

- [`saas-core-integration/`](./saas-core-integration/) — AWS-hosted SaaS core ↔ Azure platform integration. The Lumin Digital cross-cloud story.
- [`legacy-replatform/`](./legacy-replatform/) — vendor BPM and data platforms migrated to Azure-native equivalents.

Each example will eventually contain:

- A `README.md` with the scenario, the architectural narrative, and the sequence of module compositions.
- A working root-level Terraform configuration that an operator can adapt to their subscription.
- Diagrams of the resulting topology.

For now, the per-example READMEs document the planned scope and what's blocking the build (typically: real information about the target integration that hasn't been collected yet).
