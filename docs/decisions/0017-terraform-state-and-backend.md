---
id: 17
title: Terraform state is per-blast-radius Azure Storage, identity-accessed and treated as a sensitive artifact
status: accepted
date: 2026-06-08
categories: [foundation, infrastructure, security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-006]
cites_adrs: [ADR-0001, ADR-0004, ADR-0007, ADR-0009, ADR-0024]
---

# ADR 0017 — Terraform state is per-blast-radius Azure Storage, identity-accessed and treated as a sensitive artifact

## Context

State is the substrate every `apply` runs against. Three forces shape how it is stored:

- **State holds secrets.** Terraform state records resource attributes verbatim, including generated passwords, keys, and connection strings. A store that holds secrets is a sensitive artifact ([ADR 0009](./0009-secrets-ephemeral-by-default.md)): who can read it, and how it is protected, is an audit question.
- **State is a blast-radius boundary.** A single shared state file means one careless `apply` or one corrupted lock can damage the whole estate. Where the boundaries fall determines how much a mistake can reach.
- **State binds to topology.** An environment is a subscription under a management group ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)); state isolation binds to that scope vocabulary.

[ADR 0004](./0004-composition-by-output-data.md) forbids *modules* from coupling through each other's remote state. This ADR sets the backend contract and holds that no-coupling discipline at the level of separate **roots**.

## Decision

### 1. The backend is Azure Storage with native blob-lease locking

State lives in an `azurerm` backend — an Azure Storage account and blob container — using the backend's native blob-lease state locking. State stays in the adopter's own tenant. A third-party state service or non-Azure backend is an adopter exception that names the data-residency tradeoff in its own ADR.

### 2. State is treated as a sensitive artifact, like a secret store

The state account carries the posture [ADR 0009](./0009-secrets-ephemeral-by-default.md) applies to Key Vault:

- **Identity-accessed, no shared keys.** Entra ID auth only; shared-key and SAS access disabled. The pipeline reaches state through its federated/managed identity, never an account key.
- **No broad reader.** Read access to a state container is least-privilege and explicit; subscription Reader does not transitively grant data-plane access, and data-plane roles are granted per container to the identities that need them.
- **Encrypted with a customer-managed key.** The account is CMK-capable with infrastructure encryption on; the key topology is the key-management ADR's call.
- **Network-restricted.** No public blob access; reached via private endpoint from the pipeline network.
- **Access-logged.** Storage diagnostic settings emit data-plane access logs to the observability substrate ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)); anomalous reads are alertable.

### 3. State isolation is one state per blast-radius boundary, keyed by scope

There is no estate-wide state file. State is partitioned along [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)'s scope vocabulary so a mistake's blast radius is one root:

- **Per environment-subscription.** A `prod` apply cannot touch `dev` state; each environment is a hard partition.
- **Per root within an environment.** Each environment root or workload deployment has its own state key; a workload `apply` cannot corrupt foundation state, and two roots can apply concurrently.
- **Estate-wide foundation** (management-group policy assignments) has its own state at the platform scope.

The state key encodes scope role, environment, and root name. The dimensions are fixed here; the exact key string is a convention firmed up with the reference environment root.

### 4. Roots share data through published outputs, never by reading each other's state

Cross-root composition — a networking root's VNet ID consumed by a workload root — happens through published, addressable outputs: a live Azure resource resolved by a `data` source or convention, or an explicitly published outputs location. Pointing `terraform_remote_state` at another root's state file is ruled out: it couples to that root's internal layout and requires read access to a sensitive artifact (§2). A root has no read access to another root's state.

### 5. The backend is bootstrapped as code, then migrated to itself

The state account cannot store its own state before it exists. The bootstrap is a small root applied locally or by the platform pipeline, then migrated to remote state once the account exists — code, not a portal artifact ([AP-004](../anti-patterns.md#ap-004--configuration-drift)). The bootstrap tooling is open; the requirement is that the backend's own creation is code.

### 6. Remote state enables drift detection

A scheduled `plan` against each root's state opens a ticket when non-zero ([ADR 0007](./0007-change-as-code.md), [AP-004](../anti-patterns.md#ap-004--configuration-drift)). That depends on state being remote, locked, and reachable by the drift job's identity.

## What this does not decide

- **Concrete storage-account names, regions, replication (LRS/ZRS/GRS), and resource groups** — adopter data, resolved in environment roots against ADR 0024's scope vocabulary.
- **The CMK key topology** — which key, in which vault, with what rotation — is the key-management ADR's. This ADR requires CMK-readiness, not a specific key.
- **The execution pipeline** — how and where plan and apply run, and the drift-detection job — is the CI/CD ADR. This ADR sets the backend requirements that pipeline meets.
- **The exact state-key string and the per-workload granularity threshold** — the scope / environment / root dimensions are fixed; the string is firmed up with the reference root.
- **Non-Azure or third-party backends** — an adopter-exception ADR that names the data-residency tradeoff; not the default.
- **State migration and import for adopters with existing state** — an operational runbook.

## Reversibility

The load-bearing part is the isolation model, so it is fixed up front. The backend choice (azurerm storage) is moderately reversible: moving to a different store is a per-root `terraform state` migration, bounded because the backend is declared in each root's config. Isolation granularity is the asymmetric one — going coarse→fine later means splitting state and re-homing resources across files, while fine→coarse is rarely wanted — so isolation starts fine-grained. The sensitive-artifact posture (§2) and the no-raw-state-reads discipline (§4) are cheap to hold from day one and expensive to retrofit once broad readers or cross-root state reads exist; both are guarded at review.

## Consequences

**Positive.**

- State is identity-only, CMK-encrypted, network-restricted, and access-logged — a clear answer to who can read state (§2).
- A mistake's blast radius is one root, not the estate; environments are hard-partitioned and roots apply concurrently (§3).
- The no-coupling discipline of ADR 0004 holds at the root level (§4); the estate does not grow a web of cross-root state reads.
- Drift detection has the remote, locked backend it needs (§6).
- The backend binds to ADR 0024's scope vocabulary rather than a parallel topology.

**Negative — and accepted.**

- Many small state files cost more bootstrap and key-convention discipline than one large file. The alternative is a single estate-wide blast radius.
- Disabling shared-key access and brokering everything through identity is more setup than copying an access key into a pipeline. It is paid once at platform setup.
- Forbidding raw cross-root state reads makes some handoffs more verbose than a one-line `terraform_remote_state`. The verbosity is the cost of not coupling roots to each other's internals.

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — remote, locked state enables scheduled drift detection; bootstrap is code, not portal.
- [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil) — no shared keys or SAS in pipeline variables; the state plane is reached by identity.
- [ADR 0001](./0001-iac-terraform-with-avm.md) — the Terraform/AVM substrate state belongs to.
- [ADR 0004](./0004-composition-by-output-data.md) — no remote-state coupling, held at the root level (§4).
- [ADR 0007](./0007-change-as-code.md) — bootstrap and drift detection follow change-as-code.
- [ADR 0009](./0009-secrets-ephemeral-by-default.md) — state is a sensitive artifact; it carries Key Vault's access posture.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — state isolation binds to the scope vocabulary.
