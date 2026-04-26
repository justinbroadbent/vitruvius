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
