---
id: 21
title: Compliance control mapping is declared data; the control map is a derived view
status: accepted
date: 2026-06-08
categories: [security, governance, compliance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-009, AP-005, AP-012]
cites_adrs: [ADR-0003, ADR-0005, ADR-0008, ADR-0011, ADR-0016]
---

# ADR 0021 — Compliance control mapping is declared data; the control map is a derived view

## Context

[ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) sets how every policy behaves — grouped into **initiatives** (named bundles of related policies), rolled out audit-before-deny, enforced in tiers, with exemptions as first-class — and says an initiative "documents the controls it maps to — NIST CSF subcategory, GLBA Safeguards Rule section, internal risk register entry." Today that mapping is prose: no structured field carries it, and nothing checks it.

A **control** is a specific safeguard a regulator expects to exist (for example, "access to member data is restricted and reviewed"). A credit union's NCUA examination and its GLBA §501(b) safeguards obligations turn on a **control map** — for each control in scope, what implements it and what evidence proves it operates. (Which regulation implements GLBA for the adopter is itself a compliance-partner determination: for federally insured credit unions NCUA implements it via **12 CFR Part 748, Appendices A & B**; the FTC's Safeguards Rule, 16 CFR 314, applies to non-bank financial institutions. The framework-qualified identifiers below make the regime a content choice, not a schema choice.) The forces:

- **Auditors need a control map with evidence.** A list of policies is not a control map. A control map is keyed by *control*, says which controls are automated vs. manual vs. open, and links each to evidence.
- **The map must not rot.** A control map kept in a spreadsheet or wiki drifts away from the policies it describes, and the drift stays invisible until an exam finds it ([AP-009](../anti-patterns.md#ap-009--doc-rot)).
- **The platform team cannot pick the controls alone.** Which NIST CSF subcategories and GLBA sections are in scope — and whether a given Azure Policy *satisfies* a control to an examiner's standard — is a conversation with the security/compliance partners. Inventing it unilaterally produces controls that don't match the org's risk posture ([AP-012](../anti-patterns.md#ap-012--seagull-architecture)).

This ADR fixes the **control-mapping contract** — where a mapping is declared, and how the map is produced — so the catalog can be built incrementally. The control catalog itself is the partners' to supply.

## Decision

### 1. Control mappings are declared as structured data, per initiative

Every policy initiative declares which controls it provides evidence for, as a machine-readable list of **framework-qualified control identifiers** — identifiers that name both the framework and the control, e.g. NIST CSF `PR.AC-1`, NCUA `748-app-a.II`, or an internal risk-register ID. This declaration sits alongside the plain-English *intent* that ADR 0008 §1 already requires, and it extends the structured-contract principle of [ADR 0011](./0011-module-manifest.md): the manifest is where a module's structured facts live.

Because each identifier carries its framework prefix (`csf:PR.AC-1`, `ncua:748-app-a.II`, `glba:314.4(c)(1)` for an FTC-regulated adopter), the contract is framework-agnostic: an adopter can key on CSF 1.1, CSF 2.0, the applicable GLBA-implementing regulation, or an internal framework without a schema change.

### 2. The control map is derived, never hand-maintained

A generator reads the declared mappings across every initiative and emits the control map in **both directions**: control → the initiatives/policies that implement it, and initiative → the controls it serves. The map is a build artifact, regenerated from the declarations and checked for drift in CI — the source-and-derived split of [ADR 0016](./0016-software-catalog-and-backstage-contract.md): the declared mappings are the source, the map is the generated view. A derived map cannot drift from the policies it describes ([AP-009](../anti-patterns.md#ap-009--doc-rot)).

The mapping is **many-to-many** — one policy can serve several controls, and one control is often satisfied by several policies — which is precisely why the map is derived rather than kept as a hand-maintained 1:1 table.

> **In plain terms:** each policy bundle carries a checkable note saying which regulatory requirements it helps satisfy, and a program assembles the auditor's map from those notes. Nobody maintains the map by hand, so it cannot quietly go stale.

### 3. Coverage is explicit, and gaps are first-class

The derived map enumerates every control **in scope**, not only the ones already implemented. A control with no implementing policy is rendered as a declared gap — `manual` (a process control whose evidence lives outside Azure Policy) or `unimplemented` (open work) — never as silence. An auditor reading the map sees what is automated, what is manual, and what is open. A map that lists only what exists reads as falsely green; this clause forbids that.

### 4. Evidence is derived from telemetry, not assembled by hand

Per ADR 0008 and [ADR 0005](./0005-observability-substrate-and-signal-parity.md), the results of audit-mode policy evaluation already flow as telemetry into the observability substrate (the central monitoring store). The control map links each control to (a) the policy definitions that implement it and (b) the live evaluation/compliance state from that telemetry. The auditor-facing **evidence pack** is generated from substrate data, not curated by hand. Building the evidence-pack generator is separate follow-up work; what this ADR decides is that evidence is derived, not authored.

### 5. Initiative organization: per-control-family, and mappings live with the policy

Initiatives follow the `ncua-glba` README's shape — grouped by **control family** (a regulator's grouping of related controls) with plain-language names (e.g. `vitruvius-csf-pr-ac` for Identity Management & Access Control). Consistent with [ADR 0003](./0003-modules-ship-policy-and-monitoring.md), a module that ships its own `policy/` initiative declares *its* control mappings right there; the `policies/ncua-glba` bundle is the **aggregation view** across the estate, not the sole home for mappings. The derived map unions both.

### 6. The lifecycle is ADR 0008's, unchanged

Control-mapped policies still go audit-before-deny, still run tiered (sandbox/dev `Audit`, production `Deny` once the evidence supports it), and still treat exemptions as first-class. An **exemption is itself evidence** — a documented, time-boxed, owner-attributed deviation from a control — and it appears in the map against the control it touches. This ADR adds the mapping contract on top of ADR 0008; it does not revisit the lifecycle.

## What this does not decide

- **The actual control catalog** — which NIST CSF subcategories and safeguards sections are in scope, and which Azure Policy implements each, is the security/compliance-partner conversation the `ncua-glba` README flags as the blocker. That conversation also confirms the applicable GLBA regime (NCUA 12 CFR 748 vs. FTC 16 CFR 314 — see Context).
- **The map generator and its CI drift check** — §2 specifies that the map is derived and drift-checked; building the generator and wiring the check are follow-up work, not yet live.
- **The exact schema/manifest field** that carries the mappings — the shape is named here; the JSON Schema change to `module-manifest.schema.json` (and any `ncua-glba` initiative-metadata format) is a follow-up.
- **The evidence-pack generator and the auditor artifact format** — deferred, concept-first.
- **Whether a given policy satisfies a control to an examiner's standard** — that is the compliance partner's and the auditor's call, not a platform-team assertion. The contract records the *claim*; acceptance is external.
- **Framework version and revision** (CSF 1.1 vs 2.0, which Safeguards revision) — the framework-qualified identifier (§1) keeps the contract version-agnostic; the adopter and compliance team pin the framework.
- **PCI** — out of scope for this bundle by deliberate repo decision (root `README.md`).

## Reversibility

**Cheap to change (two-way door).** Mappings are declared data and the map is a regenerated artifact: change a declaration, regenerate — there is no infrastructure and no hand-maintained table to migrate. The one part worth stabilizing early is the **control-identifier vocabulary** (§1), because that is what external references — audit reports, the evidence pack, a regulator's findings — bind to; even so, framework-qualified keying keeps a vocabulary change survivable. The contract can be reshaped before the catalog grows large.

## Consequences

**Positive.**

- The control map cannot rot ([AP-009](../anti-patterns.md#ap-009--doc-rot)): it is derived from the policies in CI, not kept in a spreadsheet that drifts.
- Auditors get a control-keyed map with explicit coverage — automated, manual, and open controls all visible — and evidence derived from live telemetry rather than assembled by hand.
- The catalog is built **incrementally** with compliance partners, one control family at a time: the contract is fixed, only the content grows.
- The many-to-many reality is modeled honestly rather than forced into a brittle 1:1 table.

**Negative — and accepted.**

- Declaring mappings is per-initiative authoring toil. We accept it: it is structured data, drift-checked, and far cheaper than reconstructing a control map at exam time.
- The derived map is only as honest as its declarations — a wrong or optimistic mapping produces a wrong map. We mitigate with explicit gap controls (§3) and by keeping examiner acceptance external (a mapping is a claim, not a verdict).
- A structured control map can *imply* more assurance than audit-mode-only enforcement actually delivers. We mitigate by surfacing enforcement state (audit vs. deny, per ADR 0008) and exemptions directly in the map, so "mapped" never silently reads as "enforced."

## Cites

- [AP-009](../anti-patterns.md#ap-009--doc-rot) — the control map is derived, never forked, so it cannot rot.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — mapped policies still follow the scoped, audited lifecycle (via ADR 0008), not sweeping bans.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — modules ship their own policy and now declare its control mappings.
- [ADR 0005](./0005-observability-substrate-and-signal-parity.md) — audit-mode evaluation telemetry is the evidence substrate.
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — the policy lifecycle this contract sits on top of.
- [ADR 0011](./0011-module-manifest.md) — the structured-contract principle the control mappings extend.
- [ADR 0016](./0016-software-catalog-and-backstage-contract.md) — the same source-and-derived pattern: declared source, generated view.
