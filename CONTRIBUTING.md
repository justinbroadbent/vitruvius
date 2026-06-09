# Contributing to Project Vitruvius

This repo is a shared endeavor. Anyone with the right knowledge can — and should — contribute. The architect's job is to curate and synthesize, not to gate authorship. See [ADR 0012 — Collaborative design](docs/decisions/0012-collaborative-design.md) for the practices that govern how we work, and [AP-012 — Seagull architecture](docs/anti-patterns.md#ap-012--seagull-architecture) for the failure mode we are deliberately avoiding.

## What you can contribute

- A **new module** under `modules/<area>/<name>/`.
- A **new ADR** in `docs/decisions/`.
- A **new anti-pattern** in `docs/anti-patterns.md`.
- A **change** to an existing module, ADR, or pattern.
- A **deviation ADR** documenting a workload that does not fit a golden path.
- A **fix** to docs, scripts, or CI tooling.

If you're not sure which shape your contribution fits, open a draft PR and ask.

## How to propose something

### A new module

1. Read [`AGENTS.md`](AGENTS.md) — especially "How to add a new module."
2. Check that no existing module already covers your case. If one is close but not right, prefer modifying it (per [`docs/composition.md`](docs/composition.md)) over creating a near-duplicate.
3. Create the module directory with the layout in `AGENTS.md`. Required files: `manifest.yaml`, `README.md`, `AGENTS.md`, Terraform files, `examples/`, `tests/`.
4. Open a PR with `area:<foundation|networking|platform-services|workload-patterns>` and `kind:new-module` labels.
5. CI validates manifest schema, manifest-vs-code coherence, and module conventions.
6. Reviewers from the affected area sign off; the platform team confirms the merge.

### A new ADR

ADRs follow an RFC pattern (per [ADR 0012](docs/decisions/0012-collaborative-design.md)):

1. Copy [`docs/decisions/_template.md`](docs/decisions/_template.md); assign the next sequential ID.
2. Write the **Context** section first. If the context isn't strong enough to justify a decision, the ADR isn't ready.
3. Fill **every** section. Two are required and non-negotiable (ADR 0012 §9): **What this does not decide** — the deferred specifics, named explicitly — and **Reversibility** — cheap-to-change vs load-bearing, and the cost of unwinding. They keep the reference-vs-real boundary explicit and stop the platform from being locked into corners.
4. Open a draft PR with the `kind:rfc-adr` label.
5. The ADR is open for comment for the RFC period — default two weeks; longer for cross-cutting decisions.
6. After the RFC period, sign-off from reviewers in affected teams converts the draft to ready-for-merge.

The architect can author an ADR; the architect cannot self-approve it.

### A new anti-pattern

If you've watched something fail and the failure mode isn't already in [`docs/anti-patterns.md`](docs/anti-patterns.md), add it.

1. Use the existing entry format: name, what you see, why it happens, what it costs, what we do instead, citations.
2. Open a PR with the `kind:anti-pattern` label.
3. Reference the ADRs (existing or new) that address it. If no ADR addresses it yet, that's fine — anti-patterns can predate the decisions that respond to them.
4. After merge, the citation backbone in existing principles, ADRs, and AGENTS.md may need updates to point at the new entry.

### A deviation

If your workload doesn't fit a golden path, you don't have to fight us — you have to document the deviation. See [`docs/golden-paths.md`](docs/golden-paths.md) for the contract.

1. Open a PR adding an ADR explaining the deviation.
2. Identify the cross-cutting concerns you're taking ownership of (all six — identity, observability, secrets, networking, naming, tagging; see `docs/golden-paths.md` for the canonical list).
3. Show evidence that your reimplementation meets the same audit and operational bar as the pattern's defaults.
4. Reviewers from the platform team and the security team sign off; the deviation is the workload team's ongoing responsibility.

## Where to discuss

> This guide uses GitHub vocabulary throughout. The patterns work identically on Azure DevOps — see [ADR 0007 § Tool-platform portability](docs/decisions/0007-change-as-code.md#tool-platform-portability--github-or-azure-devops) for the GitHub ↔ ADO mapping.

Per [ADR 0012](docs/decisions/0012-collaborative-design.md), design conversations are public. Use:

- **PR comments** for design questions on a specific change.
- **GitHub issues** for cross-cutting questions, open RFCs, or "is this the right shape?" discussions.
- **Team chat (`#platform-architecture`)** for quick async questions.
- **Office hours** for synchronous deep-dives. Schedule is in the team calendar.

DM-only design conversations are an anti-pattern (AP-012). If a discussion starts in DM, summarize it in a PR comment or issue within 24 hours.

## Code style and conventions

- **Terraform.** `terraform fmt` — CI enforces it. `tflint` is recommended locally but is not yet a CI gate (see `docs/principles.md` § How these are enforced). AVM modules are the primitive layer (per [ADR 0001](docs/decisions/0001-iac-terraform-with-avm.md)); do not reimplement what AVM already wraps.
- **YAML manifests.** Two-space indent. JSON Schema validates structure. CI runs the schema against every `manifest.yaml`.
- **Markdown.** GitHub-flavored. One sentence per line is acceptable but not required.
- **Commit messages.** Imperative mood, present tense. First line ≤ 72 chars. Body explains *why*, not *what*.
- **Branch names.** `<kind>/<short-description>` — for example, `module/foundation-naming`, `adr/secrets-rotation-handler`, `anti-pattern/seagull-architecture`.

## Review and merge

- Default: at least one reviewer from the area; one platform-team reviewer for curatorial sign-off.
- Cross-cutting changes: reviewers from each affected area.
- Architect-authored work: same review path as anyone else's. The architect does not self-approve.
- ADR RFC merges: see "A new ADR" above for the full path.

## What we won't accept

- Patterns or modules that violate the principles in [`docs/principles.md`](docs/principles.md).
- ADRs without engaged context. *"We should do X"* is not a decision; it's a preference. Every ADR earns its place by explaining the alternatives and the evidence.
- Anything that re-introduces an [anti-pattern](docs/anti-patterns.md) this repo guards against. If a PR needs an exception, that's a deviation ADR — not a quiet bypass.
- Marketing copy, fluff, premature abstractions, or hypothetical-future-use code.
- Mid-tier orchestrator modules. See [ADR 0004](docs/decisions/0004-composition-by-output-data.md).

## Questions

If something in this guide is unclear, open an issue. The guide itself is open to contribution — if a process is friction without value, we should fix it.
