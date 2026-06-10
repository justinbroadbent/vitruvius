# policies/ncua-glba

Azure Policy as code mapped to the controls a credit union's regulators care about: the relevant NIST Cybersecurity Framework (CSF) subcategories and the GLBA Safeguards Rule sections.

**Status: deferred. Needs deliberate work with security and compliance partners.**

What this bundle will eventually contain:

- Per-control-family initiatives, each grouping the Azure Policy definitions that map to that family.
- A control map — for each NIST CSF subcategory (`PR.AC-1`, `DE.CM-7`, etc.) and each GLBA Safeguards section, the specific policies that implement evidence collection.
- Audit-mode tier defaults aligned with [ADR 0008](../../docs/decisions/0008-audit-before-deny-policy-lifecycle.md).
- An evidence-pack generator concept (deferred, likely lives in `concepts/` first) — auditor-facing artifacts produced from policy-evaluation telemetry.

What's blocking:

- The control map is a security/compliance team conversation, not a platform-team unilateral exercise. Inventing it without those partners produces controls that don't match the org's actual risk posture or audit expectations.
- The mapping between NIST CSF and GLBA Safeguards is well-documented externally (NCUA letter to credit unions, NIST mappings), but the **specific** Azure Policy implementations for each control require auditor-side acceptance to be useful.
- PCI is **out of scope** for this bundle by deliberate choice — see the repo-root [`README.md`](../../README.md) "What this is" section.

When the build starts, the right shape is initiative-per-control-family with clear ownership. Initiative names should match the control families in plain language (e.g., `platform-csf-pr-ac` for Identity Management & Access Control), and the evidence-pack generation is a separate concern that consumes the initiative's evaluation telemetry.

The **contract** for all of the above — how an initiative declares the controls it maps to, and how the control map and evidence pack are *derived* rather than hand-maintained — is decided in [ADR 0021](../../docs/decisions/0021-ncua-glba-control-mapping-contract.md). This bundle supplies the *content* (the actual control catalog, with security/compliance partners); ADR 0021 fixes the *shape* so that content can be added incrementally.
