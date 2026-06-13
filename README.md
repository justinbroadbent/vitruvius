# Project Vitruvius

A starter platform-architecture library for a regulated financial-services organization running on Azure with Terraform.

Named for [Vitruvius](https://en.wikipedia.org/wiki/Vitruvius), the Roman architect whose three principles — *firmitas, utilitas, venustas* (durability, utility, elegance) — translate cleanly to the review criteria every module here is held to.

New here? **[The Vitruvius Handbook](./HANDBOOK.md)** is the plain-language user's manual and manifesto — what this platform believes, what's in the box, and how to adopt it. (A print-ready [HTML version](./HANDBOOK.html) ships alongside it.)

## What this is

A composable library of Terraform modules, examples, and policy-as-code that:

- Anchors on **Azure Verified Modules (AVM)** for primitives — we don't reinvent `azurerm_*` wrappers.
- Models **both layers** of an Azure estate:
  - **Foundation** — management groups, policy, identity baseline, networking hub
  - **Workload** — opinionated patterns for common application shapes
- Bakes **observability and policy into every module** — not bolted on by a separate team.
- Treats **OpenTelemetry as the collection format** and the emission target (Azure Monitor, Datadog, …) as configuration.
- Targets **NCUA + GLBA** as the compliance posture out of the box. PCI is intentionally out of scope.

## What this is *not*

- Not a replacement for [Azure Landing Zones (ALZ)](https://aka.ms/alz) — we sit on top of it.
- Not a marketing repo. Modules are terse, opinionated, and operational.
- Not a vendor-lock-in story. Examples that integrate with SaaS providers describe the *pattern*, not the vendor's proprietary contract.

## Repo layout

```
vitruvius/
  README.md                 # this file
  AGENTS.md                 # canonical guidance for AI coding agents — read this
  CONTRIBUTING.md           # how anyone contributes a module, ADR, or anti-pattern
  LICENSE                   # Apache-2.0
  docs/
    principles.md           # firmitas / utilitas / venustas → concrete rules
    golden-paths.md         # master principle: opinionated cross-cutting, free intra-app
    composition.md          # how modules layer; what shapes are forbidden
    anti-patterns.md        # the failure modes the design exists to prevent
    ai-usage.md             # what AI is used for (and explicitly NOT used for)
    decisions/              # ADRs (each cites the anti-patterns it addresses)
      README.md             # generated index, grouped by category and status
  modules/
    foundation/             # naming, tags, diagnostic-settings, identity
    networking/             # hub (VNet, private DNS, AMPLS); firewall + spokes planned
    platform-services/      # observability-substrate; planned: secrets, container-registry
    workload-patterns/      # web-api-aks; planned: function-event-driven,
                            # data-pipeline, apim-bff (the SaaS-core integration shape)
  examples/
    reference-landingzone/  # composition end-to-end: foundation + platform-services wired
    saas-core-integration/  # planned: AWS-hosted SaaS core ↔ Azure platform — illustrative
    legacy-replatform/      # planned: vendor BPM/data platforms → Azure-native
  policies/
    ncua-glba/              # Azure Policy as code, mapped to NIST CSF / GLBA Safeguards
  concepts/
    README.md               # what concepts/ is for
    ai-chat-corpus/         # sketch: RAG chat over the repo
  schemas/
    module-manifest.schema.json  # JSON Schema for every module's manifest.yaml
  scripts/
    generate-adr-index.ps1   # regenerates docs/decisions/README.md from frontmatter (PowerShell, zero external deps)
    validate-manifests.py    # schema + manifest-vs-code coherence for every module (runs in CI)
    generate-catalog-info.py # regenerates each module's catalog-info.yaml from its manifest (drift-gated in CI)
  .github/
    workflows/
      ci.yml                # fmt, validate, terraform test, manifest validation, catalog + ADR index drift checks
    copilot-instructions.md # → AGENTS.md
```

## What's runnable today (v0.1.0)

Seven modules and two reference compositions. All experimental — module status per [ADR 0012](./docs/decisions/0012-collaborative-design.md) lifecycle. Every module ships with `manifest.yaml`, examples, and `terraform test` coverage.

| Layer | Module | What it does |
|---|---|---|
| foundation | [`naming`](./modules/foundation/naming/) | Canonical Azure resource names (pure-logic). |
| foundation | [`tags`](./modules/foundation/tags/) | Tag taxonomy + the policy initiative that enforces it. |
| foundation | [`diagnostic-settings`](./modules/foundation/diagnostic-settings/) | Substrate-routing safety-net policy initiative. |
| foundation | [`identity`](./modules/foundation/identity/) | Platform-baseline managed identities (deliberately minimal). |
| networking | [`hub`](./modules/networking/hub/) | Hub VNet, centralized private DNS, and the AMPLS. Firewall deferred to v0.2. |
| platform-services | [`observability-substrate`](./modules/platform-services/observability-substrate/) | The central LAW + App Insights store every module's diagnostics route to. |
| workload-pattern | [`web-api-aks`](./modules/workload-patterns/web-api-aks/) | Containerized HTTP API on AKS — workload identity, KV via AVM, hardening initiative. |

[`examples/reference-landingzone/`](./examples/reference-landingzone/) wires the modules together end-to-end — the worked demonstration of composition by output data (ADR 0004).

Directories with stub READMEs (`policies/ncua-glba`'s full catalog, the planned examples) document scope that's been thought through but not yet built.

See [`AGENTS.md`](./AGENTS.md) for the conventions every new module must follow, and [`modules/foundation/README.md`](./modules/foundation/README.md) for the foundation layer's overview.

## Continuous integration

Every push and pull request runs [`.github/workflows/ci.yml`](./.github/workflows/ci.yml). A change merges only when every job passes.

| Job | What it checks | Gate |
|---|---|---|
| `fmt` | `terraform fmt` — all Terraform is canonically formatted. | Blocks merge |
| `manifest` | Each `manifest.yaml` validates against the schema and matches its module's code — inputs, outputs, shipped policy/monitoring, citations. Then regenerates `catalog-info.yaml` and `CONTROL-MAP.md` and fails if either drifted from its source. | Blocks merge |
| `module` | Per module: `terraform validate` + `terraform test`. | Blocks merge |
| `example` | Per example: `terraform validate` (examples are validated, not unit-tested). | Blocks merge |
| `adr-index` | Regenerates `docs/decisions/README.md` from ADR frontmatter and fails if it drifted. | Blocks merge |
| `all` | Passes only if every job above passed — the single status branch protection requires. | The gate |

`discover` runs first to build the per-module and per-example test matrices; it is plumbing, not a check.

Two patterns run throughout. **Validate** — authored files are correct and match the code. **Drift-check** — generated views (`catalog-info.yaml`, `CONTROL-MAP.md`, the ADR index) are rebuilt and must equal what's committed, so the catalog, the compliance map, and the decision index can never silently fall out of sync with the manifests, mappings, and frontmatter they derive from. The reference pipeline is Azure DevOps ([ADR 0020](./docs/decisions/0020-cicd-azure-devops-pipelines.md)); this repo's own CI is GitHub Actions.

## License

Apache-2.0. See [LICENSE](./LICENSE).
