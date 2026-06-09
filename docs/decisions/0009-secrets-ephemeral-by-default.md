---
id: 9
title: Secrets are ephemeral by default; static secrets are documented exceptions
status: accepted
date: 2026-04-26
categories: [security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-006]
cites_adrs: [ADR-0003, ADR-0005, ADR-0007]
---

# ADR 0009 — Secrets are ephemeral by default; static secrets are documented exceptions

## Context

A **secret** is a password, key, or token a system uses to authenticate; **rotation** is replacing it periodically for safety. [AP-006 — Secret rotation toil](../anti-patterns.md#ap-006--secret-rotation-toil) is what long-lived secrets cost: senior engineering time is consumed by quarterly rotation chores; rotation procedures rot in stale documents; some secrets are quietly never rotated because rotating them breaks downstream services nobody fully understands; and audits regularly find very old secrets in production.

The trap is treating static (long-lived) secrets as the default. Once they are the default, rotation is permanently a maintenance task the platform will spend forever fighting. The fix is structural: make rotation unnecessary by default.

## Decision

Secrets are **ephemeral** — short-lived and automatically reissued — by default. The static-secret case is an explicit, documented, codified exception.

### Default mechanisms (used wherever possible)

Wherever possible, a system authenticates by proving *who it is* (an identity Azure itself vouches for) rather than presenting a stored password. Concretely:

- **Workload Identity (federated OIDC) for AKS.** Applications running in Kubernetes get short-lived federated tokens; no static service-principal credentials live anywhere.
- **Managed Identity for first-party Azure services.** A managed identity is a built-in identity Azure issues to a service — no password involved. Functions, App Service, VMs, container apps, and anything else that talks to Key Vault, Storage, SQL, Service Bus, or Event Hubs uses managed identity — never connection strings, never service-principal secrets.
- **Service Connector** for connection wiring. Endpoints and credentials are injected at deploy time via identity-based connections, not via environment variables at runtime.
- **Cert-Manager + Key Vault CSI driver** in AKS handle the TLS certificate lifecycle automatically.
- **ACME (Let's Encrypt or Azure Public CA)** for public certificates; auto-renewal is the path of least resistance and is wired in by the workload-pattern modules.

> **In plain terms:** instead of giving every service a permanent password you must keep changing (and that can leak), give it an ID badge the building itself recognizes — one that expires constantly and reissues automatically. Nothing secret sits around long enough to steal or forget.

### Static-secret exception path (used only with documentation)

When a third party requires a long-lived credential — and only then — the following requirements apply:

1. **The secret is stored in Key Vault** (Azure's secure secret store). It does not live in a pipeline variable, a `.env` file, a Helm values file, or anyone's password manager.
2. **A rotation handler is checked in.** An Azure Function (or equivalent) lives in this repo, deployed alongside the module that owns the secret. Rotation is *code*, not a document. The handler runs on a schedule; on rotation, it generates a new credential, updates Key Vault, notifies dependents to refresh, and emits an audit event.
3. **An ADR documents the exception.** Why the secret is static — typically because a third party requires a long-lived credential. The ADR includes the third party's published rotation contract and the planned re-evaluation date.
4. **Key Vault diagnostic settings emit access logs to the substrate** — our central monitoring pipeline ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)). Anomalous access patterns (off-hours reads, reads from unexpected workload identities) are alertable.
5. **Annual review.** Each static-secret exception is re-evaluated annually. If the third party has added identity-based auth in the interim, the exception closes.

### Operating principle

If a human ever rotates a secret manually outside the codified path, that is a platform failure to be addressed, not a normal operating mode. The rotation toil this ADR is designed to eliminate must not creep back in via manual exceptions.

## What this does not decide

- **Which specific static-secret exceptions exist** — each one is its own documented ADR with the vendor's rotation contract; none is pre-blessed here.
- **The rotation-handler and CSI/cert-manager implementations** — the requirement is "rotation is checked-in code," not a specific handler design.
- **The central secrets platform module** — a shared Key Vault + rotation tooling module is deferred (see the CMK / key-management work, reserved as ADR 0022 and tracked in issue #14).

## Reversibility

**A sticky default, but not a one-way door.** "Ephemeral by default" is wired into the workload patterns, so the path of least resistance is identity-based auth. Reversing it — back to a static-secret default — would re-introduce [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil), but destroys no data and breaks no contract: it is a default and a discipline. Per-exception decisions are explicitly **two-way**: when a vendor adds identity-based auth, the annual review closes the exception. What makes the default expensive to abandon is cultural momentum, not technical lock-in.

## Consequences

**Positive.**

- Senior engineering time is freed from rotation toil.
- Audit findings about old secrets become rare and explainable. Every exception has an ADR; every rotation has a checked-in handler.
- A leaked credential stays usable only as long as a short token lifetime, not until the next quarterly rotation.
- The path of least resistance for engineers is the secure path.
- The Workload Identity setup cost, once paid by the workload-pattern module, is free for every workload that adopts the pattern.

**Negative — and accepted.**

- Some Azure services and most third-party services do not yet support identity-based auth. We pay the cost of building rotation handlers for those cases. The cost decreases over time as the supported set grows.
- Workload Identity setup is initially more complex than service-principal config. The complexity is paid once, at module-author time, not per service. The workload-pattern modules wire it correctly by default; engineers consuming a pattern do not see the complexity.
- Some legacy systems require connection strings. We meet them where they are, but we treat them as deprecated dependencies and document the migration plan.

## Cites

- [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil) — what this ADR prevents.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — Key Vault diagnostic settings travel with the module.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — Key Vault access logs land in the substrate.
- [ADR 0007](./0007-change-as-code.md) — rotation handlers and exceptions follow change-as-code.
