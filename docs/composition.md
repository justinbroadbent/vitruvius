# Composition

How modules in this repo layer, and what shapes are forbidden.

## The composition rule

> **Modules consume each other's outputs. They do not import each other.**

A consumer (an example, an environment, a workload root) instantiates Module A, reads its outputs, and passes them as inputs to Module B. Modules never declare a dependency on a *sibling* module by `source = "../other-module"`. They only depend on their own constituent AVM modules.

This has one practical consequence that is non-negotiable: **there is no orchestrator module whose only job is to glue siblings together.** That shape is how component sprawl starts.

## The four areas

The repo organizes modules into four areas. The areas are conceptual; nothing prevents a consumer from composing across them.

### 1. `foundation/`

Things that every workload in the estate touches, regardless of shape. Naming, tagging, diagnostic-settings standardization, identity baselines, Azure Policy initiatives.

Foundation modules tend to be small, opinionated, and stable. They produce conventions, not infrastructure (or if they produce infrastructure, it is the kind that exists once per subscription).

### 2. `networking/`

Hub, spoke, private-endpoint patterns, DNS zones, firewall posture. Aligned with the [Cloud Adoption Framework hub-spoke topology](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/hub-spoke-network-topology) and Azure Landing Zones.

### 3. `platform-services/`

Shared services that workloads consume but do not own — the OpenTelemetry collector deployment, the central Log Analytics workspace, Key Vault patterns, the workload identity baseline, the container registry.

### 4. `workload-patterns/`

Opinionated stacks for application shapes the platform team supports — `web-api-aks`, `function-event-driven`, `data-pipeline`, `apim-bff`. A workload pattern is the largest unit of opinion this repo offers; if a team needs something a pattern does not provide, they fork the pattern's example into their own root rather than parameterizing the pattern into a Swiss-army knife.

## Layering, not lock-step

Areas suggest a typical *order* of standup (foundation → networking → platform-services → workload-patterns), but they are not a rigid pipeline. Any consumer can compose any subset.

What you should *not* do:

- Do not invent a fifth area for "things that span two areas." Either it lives in one of the four with a clear name, or it is a *consumer* (an example or environment root) that composes across them.
- Do not introduce a `common/` or `shared/` module. The four areas already cover that ground.
- Do not have a workload-pattern module depend on a *specific* foundation module by source path. It depends on the foundation module's *outputs*, which the consumer passes in.

## When to add a new module vs. modify an existing one

Add a new module when:

- A clearly new shape exists that is not a parameterization of an existing module.
- An existing module would have to grow a `type = "..."` input that switches its behavior in ways that double its surface area.

Modify an existing module when:

- The change is a strict superset of current behavior, with backward-compatible defaults.
- The change is a security or correctness fix.

If you cannot tell, ask in the PR. The wrong answer here is to fork a near-duplicate.

This is a collaborative call, not an architect-only one ([ADR 0012](decisions/0012-collaborative-design.md)). When in doubt, open a draft RFC ADR proposing the new module and let affected teams react. The contribution path is in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

Module manifests ([ADR 0011](decisions/0011-module-manifest.md)) make composition discoverable — `manifest.yaml`'s `inputs`, `outputs`, and `dependencies.avm` are the contract a consumer reads to know what they can compose against.

## The consumer's job

A consumer (an example or an environment root) is where composition actually happens. Consumers are short, declarative, and unapologetic — they wire together the modules they need and nothing else. A consumer that grows beyond a hundred lines should probably be split.
