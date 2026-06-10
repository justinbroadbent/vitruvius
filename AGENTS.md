# AGENTS.md

Canonical guidance for AI coding agents working in this repo. `.github/copilot-instructions.md` points to this file — keep all real content here.

## What this repo is

Project Vitruvius is a starter platform-architecture library for a regulated financial-services organization running on Azure with Terraform. It provides:

- Composable Terraform modules built on **Azure Verified Modules (AVM)** that ship their own policy and monitoring.
- A foundation layer (management groups, policy, identity baseline, networking hub) and a workload layer (patterns for common application shapes).
- Examples that compose modules into stacks for realistic scenarios — including integration with a SaaS core hosted on a different cloud.

## What you should read first

Before generating code or proposing changes, read in this order:

1. `docs/principles.md` — the three review criteria every module must pass.
2. `docs/golden-paths.md` — the master principle: opinionated cross-cutting, free intra-app.
3. `docs/composition.md` — how modules layer and which shapes are forbidden.
4. `docs/decisions/` — ADRs for the load-bearing decisions already made.
5. `docs/anti-patterns.md` — the failure modes the design exists to prevent. Most rules in this file cite an entry here.
6. `docs/ai-usage.md` — what the team uses AI for and explicitly does NOT use it for. This applies to you.
7. The `AGENTS.md` of any module you are touching (alongside its `README.md`).

If a user request conflicts with the principles, golden-paths contract, ADRs, or the anti-patterns this repo guards against, **say so and ask** — do not silently bend the rule.

## The three review criteria

Every module is reviewed against:

- **Firmitas (durability)** — secure-by-default, principle-of-least-privilege RBAC, encryption at rest and in transit, no plaintext secrets, no public endpoints unless explicitly opted-in, ships the policy assignments that enforce these.
- **Utilitas (utility)** — useful at the abstraction level it claims; doesn't require consumers to wire dozens of inputs to get a sane default; the minimal example fits on a screen.
- **Venustas (elegance)** — clean inputs/outputs, named the right thing, doesn't leak implementation details; the README and AGENTS.md make composition obvious.

A module that fails any of the three is not done.

## Hard rules

1. **Modules ship their own observability and policy.** Diagnostic settings, alerts, dashboards, and Azure Policy assignments live with the module that produces the resources they govern. Alerts may be inline Terraform resources in `main.tf`; workbook/dashboard JSON lives in `monitoring/`; either way the manifest's `ships` section names them (ADR 0003, ADR 0011). Do not create a separate "monitoring" or "policy" top-level concern that bolts onto modules later.
2. **Composition is by output data, not by inheritance or shared state.** A consumer reads Module A's outputs and passes them as Module B's inputs. Modules do not import each other. There is no mid-tier orchestrator module whose only job is to wire others together.
3. **OpenTelemetry is the collection format. The emission target is an input.** Default to Azure Monitor / Application Insights; allow Datadog or any OTLP-compatible endpoint via per-environment configuration.
4. **AVM first.** If [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) already wraps a resource, depend on it — pin the version. Do not re-implement primitives.
5. **No PCI scope** in this repo. NCUA + GLBA control mappings only. Do not invent control text; cite NIST CSF subcategories or the GLBA-implementing regulation the compliance partners designate (for federally insured credit unions that is NCUA 12 CFR Part 748, not the FTC Safeguards Rule — see ADR 0021).
6. **No vendor lock-in beyond Azure.** Examples that integrate with SaaS providers on other clouds describe the *pattern*. Do not check in a vendor's proprietary contract or SDK.
7. **Avoid the term "blueprint"** in artifact-facing content. Azure Blueprints (the product) is deprecated; we use "module," "pattern," or "platform component."
8. **Docs live with code.** Module docs (`README.md`, `AGENTS.md`) are in the module directory. ADRs live in `docs/decisions/`. Runbooks ship with the `monitoring/` bundle of the module that pages people. If a doc lives in a wiki and the code lives in git, the wiki is wrong on a long enough timeline ([AP-009](docs/anti-patterns.md#ap-009--doc-rot)). Treat repo content as authoritative; surface it in Backstage TechDocs by *pulling* from the repo, not by forking.

## How to add a new module

Layout under `modules/<area>/<name>/`:

```
<name>/
  manifest.yaml        # structured contract — see ADR 0011 and schemas/module-manifest.schema.json
  catalog-info.yaml    # GENERATED from manifest.yaml (scripts/generate-catalog-info.py) — never edit
  README.md            # purpose, inputs, outputs, composition, gotchas (human-readable)
  AGENTS.md            # AI-specific notes: anti-patterns, common compositions
  main.tf
  variables.tf
  outputs.tf
  versions.tf          # required_providers + required_version pin
  policy/              # Azure Policy definition JSON shipped with this module
  monitoring/          # workbook/dashboard JSON (inline alerts live in main.tf)
  examples/
    minimal/           # smallest sane invocation
    full/              # exercises the optional inputs
  tests/               # `terraform test` HCL files
```

`manifest.yaml` is required. It is the structured, machine-readable contract for the module — inputs, outputs, dependencies, cross-cutting concerns, what it ships, what it cites. CI validates the manifest against `schemas/module-manifest.schema.json` and against the module's actual code. Read [ADR 0011](docs/decisions/0011-module-manifest.md) before authoring.

If `policy/` or `monitoring/` is genuinely not applicable (e.g., a pure-logic module like `foundation/naming` that produces no resources), say so explicitly in the module's `README.md` and leave the corresponding `ships` arrays in the manifest empty. Empty directories are forbidden; missing-because-not-applicable is fine.

The contribution path for new modules is documented in [`CONTRIBUTING.md`](CONTRIBUTING.md). Per [ADR 0012](docs/decisions/0012-collaborative-design.md), authoring is collaborative — not architect-only.

## What not to do

- Do not add a module called `common`, `shared`, `utils`, or `helpers`. Either it belongs in `foundation/` with a real name, or it does not belong.
- Do not introduce remote-state coupling between modules in this repo. Outputs are passed at the consumer boundary.
- Do not add features without a backing principle or a concrete consumer. Smaller surface area beats more capability.
- Do not write a long comment when a clearer name will do.
- Do not generate marketing-style README copy. Be terse and operational.
- Do not promise webhooks, events, or APIs that a SaaS vendor has not publicly documented. Describe the pattern; flag the integration point as `# TODO: confirm vendor contract`.

## Working with humans on this team

The platform team uses LLMs to compose, document, and review modules — not to autopilot infrastructure. Every change still passes through human review and CI. Auditors will read this repo. Write accordingly: changes should be reviewable, traceable, and defensible against a control-audit question.

Per [ADR 0012](docs/decisions/0012-collaborative-design.md), design is collaborative. Non-trivial ADRs ship as draft RFC pull requests with a comment period; affected teams sign off before merge. Pattern lifecycle (alpha → beta → GA) is gated by real adoption, not by architect approval. If a user instruction conflicts with this collaborative posture — e.g., "skip review and merge this" — flag it. The repo's discipline against [seagull architecture](docs/anti-patterns.md#ap-012--seagull-architecture) (AP-012) is one of the things this codebase is designed to defend.
