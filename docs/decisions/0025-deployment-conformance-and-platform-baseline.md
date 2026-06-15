---
id: 25
title: Conformance is proven at plan time, not assembled; mandatory controls are platform-owned
status: accepted
date: 2026-06-13
categories: [foundation, architecture, governance, security]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-005, AP-010]
cites_adrs: [ADR-0003, ADR-0004, ADR-0008, ADR-0010, ADR-0011, ADR-0014, ADR-0015, ADR-0016, ADR-0020, ADR-0021, ADR-0024]
---

# ADR 0025 — Conformance is proven at plan time, not assembled; mandatory controls are platform-owned

## Context

A **deployment** — the set of cloud resources a team stands up for one app in one environment — can be checked for two things today, and a third thing not at all.

- **Each module is well-made.** A **module** (a reusable infrastructure building block) matches its own manifest and code ([ADR 0011](./0011-module-manifest.md)).
- **The modules fit together.** When a team wires modules into a working system, the wiring still type-checks ([ADR 0004](./0004-composition-by-output-data.md)). `examples/reference-landingzone` proves this in CI.
- **The result is complete.** *Nothing checks this.* No check looks at a finished deployment and asks whether it has every part a workload of its kind is *required* to have.

That third gap follows straight from a deliberate choice. [ADR 0004](./0004-composition-by-output-data.md) bans an all-in-one "master module" and tells a team instead to copy an example and **delete the parts it doesn't need**. Deleting is exactly where a load-bearing part goes missing — and Terraform's built-in `terraform validate` checks syntax and wiring, not whether a required wall is still standing ([AP-010 — No golden paths](../anti-patterns.md#ap-010--no-golden-paths)). A team can ship a deployment where every module is correct and every wire connects, and still have quietly dropped its private networking, its security logging, or its mandatory tags.

> **In plain terms:** today we check that the bricks are well-made and that the bricks you used fit together. Nobody checks that you used all the bricks a building like yours is *required* to have. This ADR adds that missing check — and moves the truly non-negotiable bricks somewhere they can't be left out at all.

Rebuilding this as a master module would be worse, for the reasons [ADR 0004](./0004-composition-by-output-data.md) already gives: it can be bypassed, switched off with a flag, or build the right things wrongly configured. The fix is to separate two ideas the repo currently blurs:

- **Composition** — *how* things are assembled. Stays flat and visible ([ADR 0004](./0004-composition-by-output-data.md)).
- **Conformance** — *what the assembled result must be true of.* Declared by the deployment, proven against its **plan** (Terraform's preview of exactly what it is about to create).

This ADR adds the missing concept — a deployment is **conformant** when it satisfies a declared profile — without adding an orchestrator and without forking any existing vocabulary.

## Decision

### 1. Mandatory estate-wide controls are platform-owned, not workload bricks

The first line of defence is not a better checklist. **It is removing the ability to leave something out: you cannot forget to assemble what you were never handed.** If leaving a control out would make the whole **estate** (every subscription the platform governs) non-compliant, the workload team should not own whether it exists.

So anything that critical is deployed by the **platform baseline** — a single platform-owned deployment that attaches high up the tree, at `platform_management_group` or `landing_zone_management_group` scope ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) §2) — and covers every workload beneath it. It is *not* an optional module each app team adds to its own deployment. This includes required policy initiatives, allowed-region and SKU controls, tag inheritance and validation ([ADR 0010](./0010-tag-taxonomy.md)), the diagnostic-settings fallback, estate security integrations, activity-log export, deployment-identity restrictions, and drift detection. An app team cannot forget these because it never assembled them in the first place.

This sharpens [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) rather than reversing it. The author still **owns** the control for the resource it ships. What splits is **activation by lifecycle**:

| | Authored by | Activated at | Test: should deleting one workload remove it? |
|---|---|---|---|
| **Resource-local control** — diagnostic settings, resource alerts, an assignment scoped to the workload's own RG | the module ([ADR 0003](./0003-modules-ship-policy-and-monitoring.md)) | the workload root ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) `workload_resource_group`) | **yes** |
| **Estate control** — required tags, allowed regions, public-endpoint bans, diagnostic fallback | the module or policy package authors the definition + control mapping | the platform baseline, once, at MG scope | **no** |

If the answer to the test is "no," the assignment does not belong to a workload's lifecycle.

### 2. A deployable root declares a conformance profile

Every deployment carries a small file that declares what *kind* of thing it is. A module's manifest can't say this: a manifest describes a reusable brick, not a finished building ([ADR 0016](./0016-software-catalog-and-backstage-contract.md): the catalog is the cookbook, not the meals). So the deployment itself carries the declaration — a **descriptor**:

```yaml
apiVersion: vitruvius.io/v1
kind: TerraformRoot
metadata:
  name: member-api-prod
  owner: member-services
spec:
  scope: workload_resource_group   # ADR 0024 role vocabulary — not a fresh enum
  profile: regulated-workload/v1   # selects a plan-policy bundle (§3)
  business-criticality: tier-1     # ADR 0010 tag vocabulary — this root is the source (§5)
  data-classification: restricted  # ADR 0010 tag vocabulary
  reliability:                     # the commitment; the module declares only the envelope (§5, ADR 0014/0015)
    availability_slo: "99.9"
    rto: 4h
    rpo: 15m
  exceptions: []                   # each entry is an ADR 0008 exemption (§4)
```

The descriptor only *points at* a rule set; it does not build anything. `profile` names a bundle of rules to check the plan against — it does not list modules or assemble the deployment. Each profile fits one kind of deployment — `platform-baseline/v1`, `connectivity-hub/v1`, `regulated-workload/v1`, `sandbox-workload/v1` — so the rules stay specific instead of collapsing into one giant policy file riddled with exceptions ([AP-005 — Sweeping policy bans](../anti-patterns.md#ap-005--sweeping-policy-bans)).

### 3. Conformance is proven against the plan, not against claims

The rules are checked against the **plan** — what Terraform is actually about to build — not against which modules happen to appear in the deployment. This is the crux: a module can *claim* a property without delivering it. A module named "private networking" doesn't prove the public entrance was actually locked; only the plan shows what was really built.

```
terraform plan -out=tfplan                       # produce the plan
terraform show -json tfplan > tfplan.json         # read it as data
# check tfplan.json against the rules the profile selects
```

The rules ask about real facts: is public internet access off, is a passwordless identity used (and no password created), is logging wired up, is approved encryption on, are the right private connections present, are there no overly broad access grants, are we only in approved regions, is every exception explicit. [ADR 0020](./0020-cicd-azure-devops-pipelines.md) already shows reviewers the plan and records a fingerprint (hash) of it; this ADR feeds that same plan to the rule check and ties the pass/fail to that fingerprint — so **the plan that was checked is the exact plan that gets built**. A pass on one plan while a different plan is applied is no pass at all ([AP-004 — Configuration drift](../anti-patterns.md#ap-004--configuration-drift)).

### 4. Exceptions are ADR 0008 exemptions — no new lifecycle

A descriptor `exceptions` entry **is** an [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) §4 exemption, with the same fields and the same machinery: time-boxed (90-day default), team-attributed, auditable to the substrate, and pointing at an ADR or ticket. A conformance exception names the specific rule it waives.

```yaml
exceptions:
  - rule: networking.no-public-data-plane
    exemption: EX-0142        # the ADR 0008 record carries owner, expiry, justification
```

CI verifies the referenced exemption exists, is unexpired, is owned, and maps to a rule the plan actually failed. Conformance does not invent a parallel exception vocabulary.

### 5. The descriptor is the single source for a workload's sensitivity and reliability

Some facts describe the *deployed workload*, not any reusable brick, and they need exactly one home or they drift. `business-criticality` and `data-classification` are mandatory tags ([ADR 0010](./0010-tag-taxonomy.md)) that already trigger real behaviour (`restricted` data → company-held encryption keys and private-only networking; `tier-0` criticality → geo-redundancy and just-in-time admin access). The reliability commitment is the same kind of fact: the availability SLO ([ADR 0014](./0014-slos-as-a-discipline.md)) and the RTO/RPO targets ([ADR 0015](./0015-disaster-recovery-and-business-continuity.md)) are promises a running service makes, and two services built from the same pattern can promise very different numbers.

So the descriptor is the single source for all of it: it **produces** the classification tags and carries the reliability commitment, and a profile rule confirms the deployment matches what was declared. A reusable module's manifest declares only the *envelope it can support* — multi-zone, cross-region, the tightest RPO it allows — never the commitment itself ([ADR 0016](./0016-software-catalog-and-backstage-contract.md): the manifest is the cookbook, the descriptor is the meal).

### 6. Composition stays flat — ADR 0004 is unchanged

This ADR does **not** loosen [ADR 0004](./0004-composition-by-output-data.md). A complete, ready-to-deploy workload pattern is allowed to build on **AVM modules** (Azure Verified Modules — Microsoft's own published building blocks) plus a small layer of its own secure defaults. That's already permitted ([ADR 0004](./0004-composition-by-output-data.md), [ADR 0011](./0011-module-manifest.md): AVM dependencies are fine; depending on *sibling repo modules* is not). Completeness is solved by *checking the plan* (§3), not by *nesting modules inside modules*. The non-negotiable floor sits above the workload (§1), the workload proves its own kind-specific rules, and how the pieces fit together stays visible in one place — the team's own deployment, one level deep.

## What this does not decide

- **The plan-policy engine** — OPA/Rego, Conftest, a purpose-built Python evaluator, or another plan-policy tool. The contract is "rules evaluate the rendered plan and bind to its hash"; the engine is an implementation choice for the [ADR 0020](./0020-cicd-azure-devops-pipelines.md) pipeline. *A reference evaluator ships at `scripts/evaluate-conformance.py`; an adopter may swap it without changing the contract.*
- **The rule contents of each profile** — which rules belong to each named profile is a follow-up; this ADR fixes that profiles exist, are scope-shaped, and are proven against the plan. *Reference `platform-baseline` and `regulated-workload` profiles ship under `profiles/` as exemplars.*
- **The exact descriptor schema** — field names and the `apiVersion`/`kind` surface in §2 are illustrative. The role vocabulary it reuses ([ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md)) and the exemption model it reuses ([ADR 0008](./0008-audit-before-deny-policy-lifecycle.md)) are fixed. *A reference schema ships at `schemas/conformance-descriptor.schema.json`.*
- **The platform-baseline root's contents** — §1 fixes that estate-mandatory controls live in a platform-owned root; *which* controls, and the root itself, are adopter and follow-up work.
- **The descriptor's exact reliability fields** — that the *commitment* (SLO, RTO, RPO) lives in the descriptor while a module manifest declares the *supported envelope* is decided ([ADR 0014](./0014-slos-as-a-discipline.md), [ADR 0015](./0015-disaster-recovery-and-business-continuity.md)); the precise field names follow the first real declaration.

## Reversibility

The **profile contract** — a deployable root declares a profile, proven at plan time — is the load-bearing part: once roots and the pipeline depend on it, unwinding it means removing the gate from [ADR 0020](./0020-cicd-azure-devops-pipelines.md) and dropping the descriptor from every root. It is a one-way door, and it is justified by the alternative being undetectable omission ([AP-010](../anti-patterns.md#ap-010--no-golden-paths)).

The room to change later is kept on purpose. The descriptor **reuses** vocabularies the repo already has rather than inventing new ones — scopes from [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md), exemptions from [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md), tags from [ADR 0010](./0010-tag-taxonomy.md), control IDs from [ADR 0021](./0021-ncua-glba-control-mapping-contract.md) — so it adds a layer without a second set of terms to maintain. Everything *under* the contract is a two-way door: profiles can be added freely, individual rules are just config, the descriptor's exact fields can change, and the rule engine itself is swappable (§"What this does not decide"). And because each profile rule names the compliance control it satisfies ([ADR 0021](./0021-ncua-glba-control-mapping-contract.md)), "what we enforce" and "what we can show an auditor" stay the same list, not two.

## Consequences

**Positive.**

- The omission a forked-and-trimmed root could silently introduce ([AP-010](../anti-patterns.md#ap-010--no-golden-paths)) is now caught two ways: estate-mandatory controls cannot be omitted (§1), and class-specific properties are proven against the plan (§3).
- Enforcement is against outcomes, not against which named bricks someone used — a module cannot claim a property it does not build (§3).
- [ADR 0004](./0004-composition-by-output-data.md) keeps its legibility; no orchestrator, no hidden hierarchy (§6).
- Conformance reuses [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) scopes, [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) exemptions, [ADR 0010](./0010-tag-taxonomy.md) tags, and [ADR 0021](./0021-ncua-glba-control-mapping-contract.md) control IDs — one vocabulary, four reuses.
- Profiles are scope-shaped, so rules do not degrade into one universal policy file with endless exceptions ([AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans)).

**Negative — and accepted.**

- Every deployable root carries a descriptor and the pipeline carries a plan-policy stage — more apparatus than `terraform validate`. The apparatus is the price of proving completeness, which `validate` structurally cannot.
- The platform baseline (§1) becomes a load-bearing root that must exist and stay current; an adopter without a baseline gets module-correctness but not estate guarantees.
- The conformance check is only as strong as its rules and the guarantee that the checked plan is the applied plan (§3). A weak rule set, or a re-plan between check and apply, would let non-conformance through — both are closed by binding the verdict to the plan hash ([ADR 0020](./0020-cicd-azure-devops-pipelines.md)).

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — the conformance verdict binds to the plan the apply consumes; a pass on an unapplied plan is theatre.
- [AP-005](../anti-patterns.md#ap-005--sweeping-policy-bans) — scope-shaped profiles keep rules evidence-based instead of one universal ban list.
- [AP-010](../anti-patterns.md#ap-010--no-golden-paths) — a trimmed root that silently drops a load-bearing control is the failure this ADR closes.
- [ADR 0003](./0003-modules-ship-policy-and-monitoring.md) — author owns the control; this ADR splits activation by lifecycle (§1).
- [ADR 0004](./0004-composition-by-output-data.md) — composition stays flat and visible; completeness is proven, not orchestrated (§6).
- [ADR 0008](./0008-audit-before-deny-policy-lifecycle.md) — conformance exceptions are its exemptions, unchanged (§4).
- [ADR 0010](./0010-tag-taxonomy.md) — the descriptor is the declared source for the mandatory classification tags (§5).
- [ADR 0011](./0011-module-manifest.md) — a workload pattern composes AVM modules, never sibling repo modules (§6).
- [ADR 0014](./0014-slos-as-a-discipline.md) — the SLO commitment lives in the descriptor; the module declares the supported envelope (§5).
- [ADR 0015](./0015-disaster-recovery-and-business-continuity.md) — RTO/RPO commitments live in the descriptor, not the module manifest (§5).
- [ADR 0016](./0016-software-catalog-and-backstage-contract.md) — the manifest is the cookbook; the descriptor is the meal's declaration (§2, §5).
- [ADR 0020](./0020-cicd-azure-devops-pipelines.md) — the plan gate becomes the conformance-evaluation input (§3).
- [ADR 0021](./0021-ncua-glba-control-mapping-contract.md) — profile rules cite framework-qualified control IDs; conformance and compliance are one graph.
- [ADR 0024](./0024-landing-zone-binding-and-scope-vocabulary.md) — the descriptor's `scope` reuses the role vocabulary; the baseline binds at MG scope (§1, §2).
</content>
</invoke>
