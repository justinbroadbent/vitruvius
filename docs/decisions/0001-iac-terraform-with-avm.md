---
id: 1
title: IaC is Terraform, anchored on Azure Verified Modules
status: accepted
date: 2026-04-26
categories: [foundation, infrastructure]
supersedes: []
superseded_by: []
cites_anti_patterns: []
cites_adrs: [ADR-0004]
---

# ADR 0001 — IaC is Terraform, anchored on Azure Verified Modules

## Context

The platform team writes **infrastructure as code (IaC)** — configuration files that build cloud resources, instead of clicking through a web portal — against Azure. The reasonable options:

- **Bicep** — Microsoft's own Azure-only language for this, with first-class Microsoft support.
- **Terraform** — works across many clouds, has a large ecosystem, and is already the team's standard.
- **Pulumi** — lets you describe infrastructure in general-purpose programming languages.
- **Azure Blueprints** — *deprecated* by Microsoft in favor of Template Specs and Deployment Stacks.

There is a second question: how much of the low-level plumbing (the raw **AzureRM** resources — Terraform's basic Azure building blocks) do we write ourselves versus reuse?

## Decision

**Terraform** is the IaC tool. We anchor every module on top of [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) — a library of pre-built Terraform modules maintained by Microsoft and published as verified modules on the Terraform Registry. Think of AVM as a trusted parts catalog.

We do **not** use Azure Blueprints (deprecated), and we do **not** hand-build primitives that AVM already provides.

## What this does not decide

- **Which AVM modules to adopt, or their pinned versions** — each module decides that for itself, in its own `versions.tf`, when the module is built.
- **The Terraform execution model and state backend** — how plans and applies run, and where Terraform's state file lives, are separate decisions (see the CI/CD and state-backend ADRs).
- **An absolute ban on Bicep** — a resource with no AzureRM/AVM coverage may justify a narrow, documented exception. The default is Terraform; the door is not nailed shut.
- **The AVM upstream-update cadence** — how quickly we pick up new AVM releases is an operational policy, not decided here.

## Reversibility

- **Terraform as the tool: load-bearing (a one-way door).** Every module, example, and CI step is written in Terraform; switching IaC tools later means rewriting the estate, not refactoring it. We accept that because Terraform is already the team's standard — adopting it costs nothing, leaving it costs a lot.
- **AVM as the anchor: moderately reversible.** AVM modules are *upstream* dependencies, declared per module in `versions.tf`. Swapping AVM for hand-written `azurerm` resources in a given module is a contained, per-module change — not estate-wide — precisely because consumers depend on a module's **outputs** (the values it hands back; ADR 0004), not on the fact that AVM sits underneath. That layer of indirection is the optionality that keeps this half of the decision cheap.

> **In plain terms:** don't reinvent the wheel. Use the well-tested community wheels (AVM), and spend the team's limited effort on the parts that are actually unique to this organization.

## Consequences

**Positive:**

- Matches the team's existing standard — no migration cost.
- AVM gives us a vetted upstream for the basics, with versioned releases and a well-defined contract. Our effort goes into opinionated *composition* (how the parts fit together), policy, and monitoring.
- Work that touches more than one cloud (e.g., the SaaS-core integration example, where part of the system lives on another cloud) is straightforward in Terraform.

**Negative / things we accept:**

- Some Azure-only features ship in Bicep before they ship in AzureRM / AVM. We accept the lag and treat it as a forcing function to wait for stability.
- AVM means tracking upstream versions and responding to breaking changes. We pin versions in `versions.tf` and take updates deliberately.

## Notes

- We avoid the word "blueprint" in this repo because Azure Blueprints (the product) is deprecated. We say "module," "pattern," or "platform component."
