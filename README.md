# Project Vitruvius

A starter platform-architecture library for a regulated financial-services organization running on Azure with Terraform.

Named for [Vitruvius](https://en.wikipedia.org/wiki/Vitruvius), the Roman architect whose three principles — *firmitas, utilitas, venustas* (durability, utility, elegance) — translate cleanly to the review criteria every module here is held to.

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
    foundation/             # naming, tagging, diagnostic-settings, identity
    networking/             # hub, spoke, private-endpoint patterns
    platform-services/      # observability, secrets, container-registry
    workload-patterns/      # web-api-aks, function-event-driven, data-pipeline,
                            # apim-bff (the SaaS-core integration shape)
  examples/
    saas-core-integration/  # AWS-hosted SaaS core ↔ Azure platform — illustrative
    legacy-replatform/      # vendor BPM/data platforms → Azure-native
  policies/
    ncua-glba/              # Azure Policy as code, mapped to NIST CSF / GLBA Safeguards
  concepts/
    README.md               # what concepts/ is for
    ai-chat-corpus/         # sketch: RAG chat over the repo
  schemas/
    module-manifest.schema.json  # JSON Schema for every module's manifest.yaml
  scripts/
    generate-adr-index.ps1  # regenerates docs/decisions/README.md from frontmatter (PowerShell, zero external deps)
  .github/
    workflows/              # fmt, validate, tflint, tfsec, checkov, terraform test
    copilot-instructions.md # → AGENTS.md
```

## Quickstart

This repo is in active scaffolding. The first runnable artifact will be `modules/foundation/naming` — see `AGENTS.md` for the conventions every new module must follow.

## License

Apache-2.0. See [LICENSE](./LICENSE).
