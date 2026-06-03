---
id: 1
title: IaC is Terraform, anchored on Azure Verified Modules
status: accepted
date: 2026-04-26
categories: [foundation, infrastructure]
supersedes: []
superseded_by: []
cites_anti_patterns: []
cites_adrs: []
---

# ADR 0001 — IaC is Terraform, anchored on Azure Verified Modules

## Context

The platform team writes infrastructure as code against Azure. Reasonable options:

- **Bicep** — Azure-native, JSON-template DSL, first-class Microsoft support.
- **Terraform** — multi-cloud, large ecosystem, the team's existing standard.
- **Pulumi** — general-purpose programming languages over the cloud APIs.
- **Azure Blueprints** — *deprecated* by Microsoft in favor of Template Specs and Deployment Stacks.

We also need to choose how much of the AzureRM resource surface we re-implement ourselves.

## Decision

**Terraform** is the IaC tool. We anchor every module on top of [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) — the joint Microsoft/HashiCorp library of vetted Terraform modules.

We do **not** use Azure Blueprints (deprecated) and we do **not** re-implement primitives that AVM already wraps.

## What this does not decide

- **Which AVM modules to adopt, or their pinned versions** — that is a per-module decision in each module's `versions.tf`, made when the module is built.
- **The Terraform execution model and state backend** — how plans/applies run and where state lives is a separate decision (see the CI/CD and state-backend ADRs).
- **An absolute ban on Bicep** — a resource with no AzureRM/AVM coverage may justify a narrow, documented exception. The default is Terraform; the door is not nailed shut.
- **The AVM upstream-update cadence** — how aggressively we consume new AVM releases is an operational policy, not decided here.

## Reversibility

- **Terraform as the tool: load-bearing (one-way door).** Every module, example, and CI step is Terraform; switching IaC tools is a full rewrite of the estate, not a refactor. The commitment is justified by it being the team's existing standard — zero migration cost to adopt, very high cost to leave.
- **AVM as the anchor: moderately reversible.** AVM modules are *upstream* dependencies declared per-module in `versions.tf`. Replacing AVM with hand-written `azurerm` resources for a given module is a contained, per-module change — not estate-wide — precisely because consumers depend on a module's **outputs** (ADR 0004), not on the fact that AVM sits underneath. That indirection is the optionality that keeps this half of the decision cheap.

## Consequences

**Positive:**

- Aligned with the existing team standard — no migration cost.
- AVM gives us a vetted upstream for primitives, with versioned releases and a well-defined contract. We focus our effort on opinionated *composition*, policy, and monitoring.
- Multi-cloud-curious work (e.g., the SaaS-core integration example, where part of the system lives on AWS) is straightforward in Terraform.

**Negative / things we accept:**

- Some Azure-only features ship in Bicep before they ship in AzureRM / AVM. We accept a lag and treat it as a forcing function to wait for stability.
- AVM requires us to track upstream versions and respond to breaking changes. We pin versions in `versions.tf` and consume updates deliberately.

## Notes

- "Blueprint" is avoided as repo terminology because Azure Blueprints (the product) is deprecated. We say "module," "pattern," or "platform component."
