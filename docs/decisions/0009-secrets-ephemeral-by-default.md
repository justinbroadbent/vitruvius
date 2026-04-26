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

[AP-006 — Secret rotation toil](../anti-patterns.md#ap-006--secret-rotation-toil) — senior engineering time is consumed by quarterly rotation tasks; rotation procedures rot in stale documents; some secrets are quietly never rotated because rotation breaks downstream services nobody fully understands; audits regularly find very old secrets in production.

The trap is treating static secrets as the default. Once they are the default, rotation is permanently a maintenance task that the platform will spend forever fighting. The fix is structural: make rotation unnecessary by default.

## Decision

Secrets are ephemeral by default. The static-secret case is an explicit, documented, codified exception.

### Default mechanisms (used wherever possible)

- **Workload Identity (federated OIDC) for AKS.** Pods get federated tokens; no static service-principal credentials live anywhere.
- **Managed Identity for first-party Azure services.** Functions, App Service, VMs, container apps, and anything else that talks to Key Vault, Storage, SQL, Service Bus, or Event Hubs uses managed identity — never connection strings, never service-principal secrets.
- **Service Connector** for connection wiring. Endpoints and credentials are injected at deploy time via identity-based connections, not via env vars at runtime.
- **Cert-Manager + Key Vault CSI driver** in AKS for TLS cert lifecycle.
- **ACME (Let's Encrypt or Azure Public CA)** for public certs; auto-renewal is the path of least resistance and is wired by the workload-pattern modules.

### Static-secret exception path (used only with documentation)

When a third party requires a long-lived credential — and only then — the following requirements apply:

1. **The secret is stored in Key Vault.** It does not live in a pipeline variable, a `.env` file, a Helm values file, or anyone's password manager.
2. **A rotation handler is checked in.** An Azure Function (or equivalent) lives in this repo, deployed alongside the module that owns the secret. Rotation is *code*, not a document. The handler runs on a schedule; on rotation, it generates a new credential, updates Key Vault, notifies dependents to refresh, and emits an audit event.
3. **An ADR documents the exception.** Why the secret is static — typically because a third party requires a long-lived credential. The ADR includes the third party's published rotation contract and the planned re-evaluation date.
4. **Key Vault diagnostic settings emit access logs to the substrate** ([ADR 0005](./0005-observability-substrate-and-signal-parity.md)). Anomalous access patterns (off-hours reads, reads from unexpected workload identities) are alertable.
5. **Annual review.** Each static-secret exception is re-evaluated annually. If the third party has added identity-based auth in the interim, the exception closes.

### Operating principle

If a human ever rotates a secret manually outside the codified path, that is a platform failure to be addressed, not a normal operating mode. The rotation toil this ADR is designed to eliminate must not creep back in via manual exceptions.

## Consequences

**Positive.**

- Senior engineering time is freed from rotation toil.
- Audit findings about old secrets become rare and explainable. Every exception has an ADR; every rotation has a checked-in handler.
- Credential leaks are bounded by token TTL, not by quarterly rotation cadence.
- The path of least resistance for engineers is the secure path.
- Workload Identity setup, once paid by the workload-pattern module, is free for every workload that adopts the pattern.

**Negative — and accepted.**

- Some Azure services and most third-party services do not yet support identity-based auth. We pay the cost of building rotation handlers for those cases. The cost decreases over time as the supported set grows.
- Workload Identity setup is initially more complex than service-principal config. The complexity is paid once at module-author time, not per service. The workload-pattern modules wire it correctly by default; engineers consuming a pattern do not see the complexity.
- Some legacy systems require connection strings. We meet them where they are, but we treat them as deprecated dependencies and document the migration plan.

## Cites

- [AP-006](../anti-patterns.md#ap-006--secret-rotation-toil) — what this ADR prevents.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — Key Vault diagnostic settings travel with the module.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — Key Vault access logs land in the substrate.
- [ADR 0007](./0007-change-as-code.md) — rotation handlers and exceptions follow change-as-code.
