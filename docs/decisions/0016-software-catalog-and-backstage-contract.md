---
id: 16
title: Software catalog contract — manifests are the source; Backstage is a derived view
status: accepted
date: 2026-06-02
categories: [foundation, integration, ai]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-009]
cites_adrs: [ADR-0006, ADR-0011]
---

# ADR 0016 — Software catalog contract — manifests are the source; Backstage is a derived view

## Context

Backstage is referenced across the design without a concrete catalog behind it:

- `manifest.yaml`'s `metadata.owner` is "a Backstage catalog component."
- `foundation/naming`'s `workload` input is "a Backstage catalog component."
- [ADR 0006](./0006-service-discovery-three-layers.md) names Backstage as the inventory-and-ownership layer.
- AGENTS.md hard rule 8 says TechDocs *pulls* from the repo rather than forking.
- The `ai-chat-corpus` concept treats Backstage Search as its prerequisite.

The manifests ([ADR 0011](./0011-module-manifest.md)) are machine-readable contracts intended to generate `catalog-info.yaml`.

Standing up Backstage — a Node service, a database, auth, plugins, a TechDocs pipeline — before there is a substrate, networking, or a landing zone to catalog is portal-before-platform. This ADR fixes the **catalog contract** — the entity model and the `manifest.yaml → catalog-info.yaml` mapping — so the foundation is catalog-ready; the server stays deferred.

## Decision

### 1. The manifest is the source of truth; catalog entities are derived

`manifest.yaml` (ADR 0011) is authoritative. `catalog-info.yaml` files are **generated** from manifests by a pure function — never hand-maintained. This keeps the catalog from rotting away from the code ([AP-009](../anti-patterns.md#ap-009--doc-rot)); a derived view cannot drift from its source.

### 2. Entity model

The estate maps onto Backstage's well-known kinds as follows:

| Vitruvius concept | Backstage kind | Notes |
|---|---|---|
| The reference platform as a whole | **Domain** (`vitruvius`) | One domain; the umbrella. |
| Each area (`foundation`, `networking`, `platform-services`, `workload-patterns`) | **System** | From `metadata.area`. |
| Each **module** | **Component**, `spec.type: terraform-module` | The reusable library/pattern artifact. |
| The owning team (`metadata.owner`) | **Group** (referenced) | `spec.owner: group:<owner>`. |
| Published service APIs | **API** | *Deferred* — derived from APIM (ADR 0006). |
| Provisioned Azure resources | **Resource** | *Deferred* — instance-level and infra-dependent. |
| People | **User** | *Deferred* — real org data, adopter-supplied. |

A Vitruvius module is modeled as the **library/pattern**, not a running instance. When an adopter *deploys* a workload using `web-api-aks`, that deployed instance becomes a `Component` of type `service` in **the adopter's** catalog — downstream of this repo and out of scope here. Vitruvius catalogs the library; adopters catalog their instances.

### 3. The `manifest.yaml → catalog-info.yaml` mapping (kind: Component)

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: <metadata.name>                    # unique within the repo today; see generation rules
  description: <metadata.description>
  tags:                                    # lowercased, kebab-case
    - <metadata.area>
    - status-<metadata.status>             # exact status preserved as a tag (lifecycle below is lossy)
    - <each cross_cutting concern that is true>     # e.g. observability, identity
    - <each cited principle>                          # firmitas | utilitas | venustas
  annotations:
    backstage.io/source-location: url:<repo>/modules/<area>/<name>/
    backstage.io/techdocs-ref: dir:.       # TechDocs ingests README.md / AGENTS.md from the repo
    vitruvius.io/cites-adrs: <spec.cites.decisions joined by ",">
    vitruvius.io/cites-anti-patterns: <spec.cites.anti_patterns joined by ",">
  links:
    - url: <repo>/modules/<area>/<name>/manifest.yaml
      title: Module manifest
spec:
  type: terraform-module
  lifecycle: <mapped from metadata.status>  # experimental->experimental, beta->experimental,
                                            # stable->production, deprecated->deprecated
  owner: group:<metadata.owner>
  system: <metadata.area>
  # dependsOn: AVM dependencies are recorded as annotations for now; modeling them as
  # Resource/Component relations is deferred until there is a consumer for the graph.
```

The `System` entities (one per area) and the single `Domain` entity are **not** per-module; they ship as a small static set under `docs/catalog/` (or a root `catalog-info.yaml`), defined once.

### 4. Generation is a pure repo artifact

A converter in `scripts/` (Go, per the team's language preference) reads every `manifest.yaml` and emits the corresponding `catalog-info.yaml`. It is deterministic and runs in CI; a drift check fails the build when a committed `catalog-info.yaml` does not match what the manifests produce.

### 5. The Backstage **deployment** is deferred behind explicit triggers

Standing up a Backstage instance happens only when **all** of:

1. The landing-zone and observability-substrate seams are real — there is an estate worth cataloging at runtime, not just a library.
2. There are enough entities that a portal beats `grep` and READMEs — rule of thumb, a dozen-plus Components/APIs across multiple teams.
3. A named owner will operate it — Backstage is a product, not a deploy.
4. Backstage Search / TechDocs is a demonstrated need (the `ai-chat-corpus` concept's own gate).

Until then, the contract above makes the foundation catalog-ready at zero operating cost.

## What this does not decide

- **The Backstage instance itself** — hosting, auth (Entra ID), plugin set, TechDocs publishing pipeline, and the catalog *discovery* mechanism (static `Location` entities vs GitHub auto-discovery) are all deployment concerns, gated by §5.
- **The org `Group` / `User` hierarchy** — real teams and people are adopter data; we reference `group:<owner>` but do not define the org tree.
- **`API` and `Resource` entities** — deferred until APIM (ADR 0006) and real deployed instances exist to derive them from.
- **The adopter-side instance catalog** — deployed workloads are downstream; this ADR catalogs the library, not anyone's running estate.
- **When the converter is built** — the mapping is decided here; the generator and its CI drift check are a separate work item.
- **Entity-name collisions at scale** — module names are unique across the repo today; if a future module reuses a name across areas, the generator prefixes with the area. The exact namespacing scheme can firm up when (if) that collision is real.

## Reversibility

**Cheap to change (two-way door) — by construction.** `catalog-info.yaml` files are *generated*, so nothing is hand-maintained to migrate: change the mapping, regenerate, done. There is no infrastructure and no data, so blast radius is near zero. Today almost nothing consumes these entities, which is precisely why deciding the shape now is cheap — the cost rises only once a live Backstage, dashboards, or relations reference entity names, so the one thing worth getting stable early is the **naming/namespace scheme** (it is the only field external references bind to). Even the deferred deployment is reversible: a Backstage instance can be torn down without touching the foundation, because the catalog is derived from the repo, not the other way around.

## Consequences

**Positive.**

- The Backstage references across the design (`owner`, `workload`, ADR 0006, AGENTS rule 8) resolve to a concrete, checkable catalog.
- The foundation is catalog-ready at zero operating cost; an adopter can point their existing Backstage at this repo and get a populated catalog immediately.
- The catalog cannot rot (AP-009): it is derived from the manifests in CI, not forked.
- The repo's own structure (domain → area → module) is reflected one-to-one in the catalog hierarchy.

**Negative — and accepted.**

- A mapping is a thing to maintain as the manifest schema evolves. We accept it; the mapping is small and the converter's drift check catches divergence.
- Several Backstage kinds (API, Resource, User) stay unused until runtime exists. We accept the partial model rather than invent instance-level entities we cannot yet derive.
- The `status → lifecycle` mapping is lossy (beta collapses into `experimental`). We mitigate by preserving the exact `status` as a `status-<x>` tag.

## Cites

- [AP-009](../anti-patterns.md#ap-009--doc-rot) — the catalog is derived, never forked, so it cannot rot.
- [ADR 0006](./0006-service-discovery-three-layers.md) — Backstage is the inventory-and-ownership layer; this ADR makes its catalog concrete.
- [ADR 0011](./0011-module-manifest.md) — the manifest is the source this catalog is derived from.
- `concepts/ai-chat-corpus/` — treats Backstage Search as its prerequisite.
