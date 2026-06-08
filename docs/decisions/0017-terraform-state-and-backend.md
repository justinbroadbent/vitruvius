---
id: 17
title: Terraform state is per-blast-radius Azure Storage, identity-accessed and treated as a sensitive artifact
status: proposed
date: 2026-06-08
categories: [foundation, infrastructure, security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-006]
cites_adrs: [ADR-0001, ADR-0004, ADR-0007, ADR-0009, ADR-0024]
---

# ADR 0017 — Terraform state is per-blast-radius Azure Storage, identity-accessed and treated as a sensitive artifact

## Context

[ADR 0001](./0001-iac-terraform-with-avm.md) chose Terraform on AVM and explicitly deferred one thing: "how plans/applies run and where state lives is a separate decision (see the CI/CD and state-backend ADRs)." This is the state-backend half of that promise. (The execution/pipeline half is the CI/CD ADR, roadmap #4.)

State is the substrate every `apply` in the estate runs against, and it is currently undecided — which means it is also undefended. Three forces make this a P0:

- **State holds secrets.** Terraform state records resource attributes verbatim, including generated passwords, keys, and connection strings. By the logic of [ADR 0009](./0009-secrets-ephemeral-by-default.md), a store that holds secrets is a sensitive artifact: an examiner *will* ask who can read it and how it is protected. "A storage account someone clicked together with its access keys shared in a pipeline variable" is the failure mode.
- **State is a blast-radius boundary.** A single shared state file means one careless `apply` (or one corrupted lock) can damage the whole estate. Where the boundaries fall determines how much a mistake can hurt.
- **State binds to topology.** [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) just decided that an environment is a subscription under an ALZ management group. State isolation has to bind to that scope vocabulary, not invent its own.

[ADR 0004](./0004-composition-by-output-data.md) forbids *modules* from coupling through each other's remote state, but says nothing about the backend itself or about how separate **roots** share data. This ADR fixes the backend contract and extends ADR 0004's no-coupling discipline up one level, to roots.

## Decision

### 1. The backend is Azure Storage with native blob-lease locking

State lives in an `azurerm` backend — an Azure Storage account + blob container — using the backend's **native blob-lease state locking** (no separate lock table needed). State stays **in the adopter's own tenant** by default; we do not route regulated-FS state through a third-party state service. Terraform Cloud / HCP or any non-Azure backend is an adopter exception that must name the data-residency tradeoff in its own ADR — it is not the default.

### 2. State is treated as a sensitive artifact, like a secret store

The state account inherits the posture [ADR 0009](./0009-secrets-ephemeral-by-default.md) applies to Key Vault:

- **Identity-accessed, no shared keys.** Azure AD / Entra auth only; storage-account **shared-key and SAS access are disabled**. The pipeline reaches state through its federated/managed identity (ADR 0009), never an account key in a pipeline variable.
- **No broad reader.** Read access to a state container is least-privilege and explicit. "Subscription Reader can read all state" is forbidden — Reader does not transitively grant data-plane access, and data-plane roles are granted per container to the identities that need them.
- **Encrypted with a customer-managed key.** The account is CMK-capable with infrastructure encryption on; the key topology is the CMK ADR's call (roadmap #14), this ADR only requires CMK-readiness.
- **Network-restricted.** No public blob access; reached via private endpoint / service endpoint from the pipeline network.
- **Access-logged to the substrate.** Storage diagnostic settings emit data-plane access logs to the observability substrate ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)); anomalous state reads (off-hours, unexpected identity) are alertable — the same treatment ADR 0009 gives Key Vault.

### 3. State isolation is one state per blast-radius boundary, keyed by scope

There is no single estate-wide state file. State is partitioned along [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)'s scope vocabulary so a mistake's blast radius is one root:

- **Per environment-subscription.** A `prod` apply can never touch `dev` state; each environment (subscription) is a hard partition.
- **Per root within an environment.** Each environment root / workload deployment has its own state key, so a workload `apply` cannot corrupt foundation state, and two roots can apply concurrently.
- **Estate-wide foundation** (e.g. management-group policy assignments) gets its own state at the platform scope.

The state **key** encodes those dimensions — scope role, environment, root name. The exact key string is a convention to firm up with the reference environment root (roadmap #7); the *dimensions* are decided here.

### 4. Roots share data through published outputs, never by reading each other's state

Cross-root composition (e.g. a networking root's VNet ID consumed by a workload root) happens through **published, addressable outputs** — a live Azure resource resolved by a `data` source or convention, or an explicitly published outputs location — **not** by pointing `terraform_remote_state` at another root's state file. Reading another root's raw state couples to its internal layout and would require granting read access to a sensitive artifact (§2), reintroducing one level up exactly the coupling [ADR 0004](./0004-composition-by-output-data.md) forbids between modules. A root has no read access to another root's state. The publish-and-consume mechanism is the consumer's to choose; reaching into raw state is the part that is ruled out.

### 5. The backend is bootstrapped as code, then migrated to itself

The state account is a chicken-and-egg: it cannot store its own state before it exists. The bootstrap is **codified** (a small root applied locally or by the ALZ platform pipeline, then migrated to remote state once the account exists) and checked in — never clicked into existence ([AP-004](../anti-patterns.md#ap-004--configuration-drift)). The exact bootstrap tooling is deferred; the requirement is that the backend's own creation is code, not a portal artifact.

### 6. Remote state is what makes drift detection possible

Per [ADR 0007](./0007-change-as-code.md) and [AP-004](../anti-patterns.md#ap-004--configuration-drift), CI runs scheduled `plan` against each root's state; a non-zero plan opens a ticket. That capability depends on state being remote, locked, and reachable by the drift job's identity. The pipeline that runs it belongs to the CI/CD ADR (roadmap #4); this ADR guarantees the backend it binds to.

## What this does not decide

- **Concrete storage-account names, regions, replication (LRS/ZRS/GRS), and resource groups** — adopter data, resolved in environment roots against ADR 0024's scope vocabulary.
- **The CMK key topology** — which key, in which vault, with what rotation — is the key-management ADR (roadmap #14). This ADR requires CMK-readiness, not a specific key.
- **The execution pipeline** — how/where plan and apply run, and the drift-detection job itself, is the CI/CD ADR (roadmap #4). This ADR sets the backend requirements that pipeline must meet.
- **The exact state-key string and the per-workload granularity threshold** — the dimensions (scope / environment / root) are decided; the string and how finely workloads split is firmed up with the reference root (roadmap #7).
- **Non-Azure / third-party backends** — allowed only as an adopter exception ADR that names the data-residency tradeoff; not the default.
- **State migration/import for adopters with existing state** — an operational runbook, not part of this contract.

## Reversibility

**Mixed, and the load-bearing part is the isolation model — so we get that right now.** The backend *choice* (azurerm storage) is moderately reversible: moving to a different store is a per-root `terraform state` migration — mechanical, but it touches every root, and it is bounded because the backend is declared in each root's config. The **isolation granularity** (§3) is the expensive-to-reverse part, and asymmetrically so: going coarse→fine later means splitting state and re-homing resources across files (painful, error-prone), while fine→coarse is rarely wanted. So we commit to fine-grained, per-blast-radius isolation up front, because the cheap direction to travel is to *start* split. The sensitive-artifact posture (§2) and the no-raw-state-reads discipline (§4) are one-way-door-ish in the same sense as ADR 0004: cheap to hold from day one, expensive to retrofit once broad readers or cross-root state reads exist — which is why both are guarded at review, not by tooling, from the start.

## Consequences

**Positive.**

- State stops being an undefended secret store: identity-only access, no shared keys, CMK, network-restricted, and access-logged — an answer to the examiner's "who can read state?" ([ADR 0009](./0009-secrets-ephemeral-by-default.md) logic applied to the state plane).
- A mistake's blast radius is one root, not the estate; environments are hard-partitioned and roots apply concurrently (§3).
- ADR 0004's no-coupling discipline holds at the root level too (§4); the estate does not silently grow a web of cross-root state reads.
- Drift detection (AP-004) has the remote, locked backend it needs (§6).
- The backend binds to ADR 0024's scope vocabulary instead of inventing a parallel topology.

**Negative — and accepted.**

- Many small state files cost more bootstrap and key-convention discipline than one big one. We accept it: the alternative is a single estate-wide blast radius, which is the failure this ADR exists to prevent.
- Disabling shared-key access and brokering everything through identity is more setup than copying an access key into a pipeline. We accept it — it is paid once at platform-setup time and is the whole point of ADR 0009.
- Forbidding raw cross-root state reads makes some handoffs more verbose than a one-line `terraform_remote_state`. We accept the verbosity as the cost of not coupling roots to each other's internals (the ADR 0004 tradeoff, one level up).

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — remote, locked state is what makes scheduled drift detection possible; bootstrap is code, not portal.
- [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil) — no shared keys/SAS in pipeline variables; the state plane is reached by identity, not a long-lived credential.
- [ADR 0001](./0001-iac-terraform-with-avm.md) — fulfills the state-backend decision ADR 0001 deferred.
- [ADR 0004](./0004-composition-by-output-data.md) — extends "no remote-state coupling" from modules up to roots (§4).
- [ADR 0007](./0007-change-as-code.md) — bootstrap and drift detection follow change-as-code.
- [ADR 0009](./0009-secrets-ephemeral-by-default.md) — state is a sensitive artifact; it inherits Key Vault's access posture.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — state isolation binds to the scope vocabulary (environment = subscription).
