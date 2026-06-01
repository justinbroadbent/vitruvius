# Principles

Every module in this repo is reviewed against three criteria, borrowed from Vitruvius's *De Architectura*: **firmitas, utilitas, venustas** — durability, utility, elegance. They sound abstract; the rules below make them operational.

## Firmitas — durability

A module is durable when it is secure, observable, and recoverable by default.

A reviewer should be able to answer **yes** to all of:

- Are all data planes encrypted in transit and at rest, with customer-managed keys *available* (not necessarily required) as an opt-in?
- Are public endpoints disabled by default? If a public endpoint is supported, is it gated behind an explicit boolean input?
- Does the module emit diagnostic settings to a Log Analytics workspace passed in as an input — without the consumer having to wire it manually?
- Does the module ship the Azure Policy assignments that enforce its own security posture (in `policy/`)?
- Is RBAC granted at the narrowest scope that works (resource > resource group > subscription)? No `Owner` or `Contributor` on subscriptions unless justified in a comment.
- Does the module have at least a `minimal` and `full` example, and at least one `terraform test` case that validates the secure-defaults invariant?

## Utilitas — utility

A module is useful when consumers reach for it because it solves a real problem at the right abstraction level.

- The minimal example fits on a screen. If it does not, the module is doing too much or asking for too much.
- Optional inputs default to the secure, sane choice. Required inputs are only those without a defensible default.
- The module's *outputs* are the contract — they are stable, named clearly, and complete enough that downstream modules don't need to query Azure to look up state.
- Naming: a module named `web-api-aks` produces a runnable web API on AKS. Not "the parts you need to assemble a web API." If the seams matter, split it; if they don't, don't expose them.
- The module solves an actual demonstrated need. Modules built for hypothetical future use cases are deleted on review.

## Venustas — elegance

A module is elegant when reading it teaches you something and editing it doesn't surprise you.

- Inputs and outputs are named for what they *are*, not for the resource type that happens to back them. (`log_workspace_id`, not `azurerm_log_analytics_workspace_id`.)
- The README and `AGENTS.md` explain *why* the module exists, *what* it composes with, and *what to avoid* — in that order.
- No commented-out code, no `TODO` without a date or owner, no leftover marketing copy.
- The module does one thing. If you find yourself describing it with "and," consider splitting.
- Comments explain non-obvious *why*, never *what*.

## How these are enforced

**Today**, CI runs `terraform fmt -check`, `terraform validate`, and `terraform test` per module and example, plus an ADR-index drift check. That is the full set of automated gates currently wired — see the pipeline definition.

**Planned** (not yet wired; do not describe as live in audit-facing material until they are):

- Static analysis: `tflint`, `tfsec`/`checkov` security scanning.
- Manifest validation: `manifest.yaml` checked against `schemas/module-manifest.schema.json` and cross-checked against `variables.tf`/`outputs.tf` for parity (ADR 0011).
- A PR checklist confirming the firmitas/utilitas/venustas review for any new or modified module.
- An automated first-pass review (CI check, Copilot prompt, or other tooling) that surfaces criteria violations for human reviewers; humans still own the merge.

The distinction is deliberate: this repo's whole posture (AP-009) is that docs must not overstate reality. A control described as live when it is not is exactly the audit-finding this section exists to avoid.
