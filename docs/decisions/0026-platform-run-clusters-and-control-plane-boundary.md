---
id: 26
title: Clusters are platform-run; Terraform stops at the Azure control plane
status: accepted
date: 2026-07-07
categories: [infrastructure, architecture, security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-006, AP-010]
cites_adrs: [ADR-0001, ADR-0004, ADR-0005, ADR-0006, ADR-0009, ADR-0018, ADR-0024]
---

# ADR 0026 — Clusters are platform-run; Terraform stops at the Azure control plane

## Context

The workload patterns run on Kubernetes: `web-api-aks` federates a workload's identity into an **AKS** cluster (Azure Kubernetes Service — Azure's managed Kubernetes) via the cluster's **OIDC issuer URL**, with no shared secret ([ADR 0009](./0009-secrets-ephemeral-by-default.md)). Until now the cluster itself was undecided — the pattern took the issuer URL as an input and left "whose cluster?" open. Two questions were unanswered, and both are load-bearing:

- **Who runs the clusters?** If every workload team stands up its own, the estate grows a fleet of divergently-configured clusters, each a security posture to audit and an upgrade treadmill to staff — the Kubernetes version of [AP-010 — No golden paths](../anti-patterns.md#ap-010--no-golden-paths).
- **Where does this repo's Terraform stop?** A cluster has two layers: the Azure resource (the control plane, node pools, its network attachment) and the Kubernetes objects *inside* it (namespaces, deployments, ingress, in-cluster RBAC). Terraform can manage both, but managing the inside couples platform Terraform to application release cadence and pulls `kubernetes`/`helm` providers — and their credentials — into every plan.

## Decision

### 1. Clusters are platform-run; workloads federate in

The platform team runs the clusters. Workload teams never operate their own; a workload's relationship to a cluster is **federation, not ownership**: the cluster exposes its OIDC issuer URL as an output, the workload pattern consumes it as an input, and the workload's identity is a short-lived federated token ([ADR 0009](./0009-secrets-ephemeral-by-default.md)). The reference implementation is [`modules/platform-services/aks-cluster`](../../modules/platform-services/aks-cluster/).

### 2. The cluster's security posture is fixed, not input-tunable

The posture travels with the module and is not reachable through inputs: a **private API server** (no public control plane, [ADR 0018](./0018-network-topology-hub-spoke.md)), **Entra ID + Azure RBAC with local accounts disabled** (there is no cluster password to steal or rotate — [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil)), **OIDC issuer and workload identity enabled** (the federation seam of §1), **diagnostics to the substrate** ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)), and **automatic node-image and Kubernetes patching**. A consumer who needs a different posture forks the module and owns the fork; they do not get a flag. Tunables (node pool shape, CIDRs, upgrade channel) stay tunable — the line is *posture vs. sizing*.

### 3. The module decides posture, never infrastructure

Everything concrete arrives as an input resolved at the consumer boundary: the subnet the nodes join, the private DNS zone, the Log Analytics workspace, the admin groups, the region ([ADR 0004](./0004-composition-by-output-data.md), [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)). The real network is not yet known; the module must keep working no matter what it turns out to be.

### 4. Terraform stops at the Azure control plane

This repo's Terraform manages the cluster **as an Azure resource** and goes no deeper. Kubernetes-internal objects — namespaces, deployments, services, ingress, in-cluster RBAC bindings — belong to the workload team's own delivery mechanism, not to platform Terraform. No module in this repo introduces a `kubernetes` or `helm` provider or resources. The workload pattern's job ends at handing the app team the `ServiceAccount` annotations that activate federation; what the app team deploys behind them is theirs.

> **In plain terms:** the platform builds and guards the building; each team furnishes its own office. The platform hands over a keycard (the federated identity), not a master key — and the platform's blueprints describe the building, never the furniture.

## What this does not decide

- **Cluster count and topology** — one shared cluster vs. per-environment vs. per-workload-class is a capacity and isolation decision made with real workloads, expressed in environment roots. The module builds *a* cluster; how many, where, and what shares them is the adopter's.
- **The in-cluster delivery mechanism** — GitOps (Flux, Argo CD) vs. pipeline-applied manifests, and who operates it, is deferred until a real workload team exists to choose with. §4 fixes only the *boundary*: whatever the mechanism, it is not this repo's Terraform.
- **User node pools** — the reference module ships one zone-redundant system pool; pools per workload class follow the first real workload's shape.
- **The service mesh** — in-cluster runtime resolution and mTLS remain [ADR 0006](./0006-service-discovery-three-layers.md)'s.
- **The public ingress edge** — how traffic *enters* the estate (edge product, WAF posture, TLS termination, DDoS tier) is a deliberately open decision; the network it would attach to is unknown. It gets its own decision when a real workload needs a public entrance.
- **Concrete sizing and versions** — node SKUs, CIDR values, Kubernetes version, and upgrade-channel choice are inputs with hardened defaults, per environment.

## Reversibility

- **Platform-run (§1) and the control-plane boundary (§4) are load-bearing (one-way doors).** Workload teams build no cluster-operations muscle and their delivery tooling assumes the boundary; reversing either means re-staffing cluster operations per team, or threading `kubernetes` providers and their credentials through platform plans — both estate-wide changes. They are the commitment this ADR makes.
- **The posture items (§2) are individually revisable** — each is one module change shipped through review, or a documented fork. Fixed is not frozen; it means *not silently tunable*.
- **Everything deferred is a two-way door by construction** — cluster topology, delivery tooling, node pools, and the ingress edge are decisions the adopter (or a follow-up ADR) makes later, with information this repo does not have.

## Consequences

**Positive.**

- One hardened cluster posture to audit instead of one per team; the golden path gets a real cluster to land on.
- The workload seam is a single string (the issuer URL) crossing the boundary with no secret — composition-by-output at its simplest.
- Platform plans never hold Kubernetes credentials; the blast radius of a Terraform apply ends at the Azure control plane.
- The module works against any network the estate turns out to have, because it owns none of it.

**Negative — and accepted.**

- The platform team is now a cluster operator, with the upgrade and capacity duties that implies. That is the point: the cost is paid once, by the team best placed to pay it.
- Workload teams needing an in-cluster capability the platform hasn't provided must ask or fork, rather than kubectl-ing it into a cluster they own. The friction is the audit story.
- Until the in-cluster delivery decision is made, early workloads carry their own interim mechanism. We accept interim variety inside the boundary over deciding tooling with no real consumer.

## Cites

- [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil) — no cluster password exists; access is identity, federation is secretless.
- [AP-010](../anti-patterns.md#ap-010--no-golden-paths) — one platform-run cluster posture instead of per-team cluster reinvention.
- [ADR 0001](./0001-iac-terraform-with-avm.md) — the cluster module is built on a pinned AVM module.
- [ADR 0004](./0004-composition-by-output-data.md) — the issuer-URL seam is composition by output data.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — cluster diagnostics land in the substrate.
- [ADR 0006](./0006-service-discovery-three-layers.md) — in-cluster runtime resolution and the mesh stay decided there.
- [ADR 0009](./0009-secrets-ephemeral-by-default.md) — workload identity federation; local accounts disabled.
- [ADR 0018](./0018-network-topology-hub-spoke.md) — the private cluster lives in the platform network.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — scopes and placement arrive as resolved inputs.
