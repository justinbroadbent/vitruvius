# Project Vitruvius — A Platform Architecture White Paper

*A reference platform-architecture library for a regulated financial-services organization on Azure and Terraform.*

---

## 1. What Vitruvius is, and what it is for

Vitruvius is a **composable library of architectural decisions, Terraform modules, and policy-as-code** that together describe how a regulated financial-services organization runs workloads on Azure. It is named for the Roman architect whose three principles — *firmitas, utilitas, venustas* (durability, utility, elegance) — are the review criteria every module is held to.

It is deliberately a **reference foundation, adopted in whole or in part**, not a description of one organization's running estate. The value is in the *contracts, principles, and seams* — the shape of good decisions — rather than in a committed concrete topology. An adopting organization takes the parts that fit, supplies its own infrastructure specifics, and extends from there.

Three commitments distinguish it from a generic "Azure best practices" repository:

- **Opinions are recorded as decisions, with their reasoning.** Twenty-one Architecture Decision Records (ADRs) state not just *what* but *why*, what each decision deliberately leaves open, and how reversible it is.
- **Cross-cutting concerns are built in, not bolted on.** Every module ships its own policy and monitoring; observability and governance are properties of a module, not a separate team's later project.
- **The design knows what it refuses to do.** Twelve named anti-patterns define the negative space — the failure modes the architecture exists to prevent — and every decision cites the ones it addresses.

The compliance posture is **NCUA and GLBA** out of the box. PCI is intentionally out of scope.

---

## 2. The design philosophy

### Firmitas, utilitas, venustas

The three principles are concrete review criteria, not slogans. *Firmitas* (durability): does the decision hold up under failure, audit, and time? *Utilitas* (utility): does it make the right thing the easy thing for the teams who consume it? *Venustas* (elegance): is it legible — can someone read it and understand what is deployed and why?

### Golden paths, not gold cages

A workload-pattern module is a paved road: adopt it and every cross-cutting concern — identity, observability, secrets, networking, naming, tagging, deployment ledger — comes for free. Deviate from it and you own those concerns yourself, plus a decision record explaining why. The road is so much easier than the alternative that almost no one leaves it, but no one is forbidden from leaving. This is the answer to two opposite failures: the absence of paved roads (every team reinvents incompatible primitives) and the overbroad mandate (rules that paint engineers into corners).

### Decide the contract; defer the specifics

The single most important habit in the repository. Each decision fixes a *shape* — an interface, a vocabulary, a seam — and defers the *concrete values* (CIDRs, subscription IDs, regions, vendor choices) to the adopter or a follow-up. Interfaces are cheap to keep stable; concrete topology is expensive to unwind. Every ADR carries two required sections that enforce this: **"What this does not decide"** names the open specifics explicitly, and **"Reversibility"** classifies the decision as a cheap two-way door or a load-bearing one-way door and states the cost of undoing it.

### The anti-patterns are the negative space

The architecture is, in large part, the deliberate avoidance of twelve well-attested failure modes:

| | Anti-pattern | The failure |
|---|---|---|
| AP-001 | Bolted-on monitoring | A separate team adds telemetry after the fact; it drifts from the resources it describes. |
| AP-002 | Telemetry dumping ground | Everything is collected, nothing is curated; cost climbs, answers get harder. |
| AP-003 | Hard-coded service endpoints | DNS baked into config; every move becomes a cross-team project. |
| AP-004 | Configuration drift | Portal changes accumulate; Terraform becomes untrusted. |
| AP-005 | Sweeping policy bans | Overbroad policy with no exemption path; engineers route around it. |
| AP-006 | Secret rotation toil | Static secrets as the default; rotation is permanent manual labor. |
| AP-007 | Change-management theater | CAB ceremony that approves what it cannot evaluate while emergencies bypass it. |
| AP-008 | Tag chaos | Free-form tags; cost and policy targeting become impossible. |
| AP-009 | Doc rot | Documentation that lives far from code and silently goes wrong. |
| AP-010 | No golden paths | Total freedom produces incompatibility and reinvention. |
| AP-011 | Lower-env signal gap | Production is monitored, lower envs aren't; regressions surface in production. |
| AP-012 | Seagull architecture | An architect designs in isolation and issues edicts nobody can adopt. |

Each ADR names the anti-patterns it blocks. Reading the two lists together is the fastest way to understand the architecture: the decisions are the moves, the anti-patterns are why the moves are necessary.

---

## 3. How decisions are made and recorded

Three decisions govern the *method* itself, and they are what make the rest trustworthy.

**Decisions are recorded, with reasoning and reversibility (the ADR discipline).** Every non-trivial choice is an ADR: context, decision, what it does not decide, reversibility, consequences, and the anti-patterns and prior ADRs it cites. The records are flat, numbered, and indexed by a generated table that CI keeps in sync with the files.

**The module contract is structured data (ADR 0011).** Every module ships a `manifest.yaml` — a machine-readable contract describing its semantic inputs and outputs, the cross-cutting concerns it participates in, the policy and monitoring it ships, its AVM dependencies, and the ADRs and anti-patterns it cites. HCL stays authoritative for implementation; the manifest is authoritative for the semantic metadata HCL cannot express. This single artifact serves humans, auditors, AI agents, and the developer portal at once, and it is the source the software catalog is derived from. A JSON Schema validates it; CI checks the manifest against the code.

**Design is collaborative, not issued from above (ADR 0012).** This is the antidote to AP-012. Non-trivial ADRs ship as draft RFCs open to comment from affected teams; an architect can author a decision but cannot self-approve it. Patterns graduate (experimental → beta → stable) by real adoption, not by approval. The point is that opinions about cross-cutting concerns are formed *from* what engineers learn in practice, not in spite of it.

---

## 4. The architecture, by theme

### 4.1 The infrastructure foundation

**Terraform, anchored on Azure Verified Modules (ADR 0001).** Terraform is the IaC tool — the team's standard and multi-cloud-capable. Every module is built on top of AVM, the joint Microsoft/HashiCorp library of vetted modules; the repository does not re-implement primitives AVM already wraps. Azure Blueprints (deprecated) is rejected.

**Composition is by output data; there are no orchestrator modules (ADR 0004).** Modules never import each other. A consumer instantiates module A, reads its outputs, and passes them as inputs to module B — composition happens only at the consumer boundary (an example or an environment root). This refusal to build a middle tier of orchestrators is what keeps the estate legible: at one level of indirection you can see exactly what is deployed and how it is wired. It is a one-way door held by review discipline, because once orchestrators exist they attract more orchestrators.

**Vitruvius binds to Azure Landing Zones by role; it does not own the hierarchy (ADR 0024).** The management-group tree, the subscriptions, and the address space belong to the adopter's ALZ deployment. Modules refer to scopes through a small named vocabulary — `platform_management_group`, `landing_zone_management_group`, `environment_subscription`, `workload_resource_group` — resolved to real IDs in the environment root. A module receives a scope by role and never parses an ID to infer it. An environment is a subscription boundary. This is the seam that lets the same modules drop onto any conformant ALZ tree.

**State is a per-blast-radius, identity-accessed, sensitive artifact (ADR 0017).** Terraform state holds secrets, so it is treated like a secret store: an in-tenant Azure Storage backend with native blob-lease locking, identity-only access (no shared keys), customer-managed-key encryption, network restriction, and access logging. There is no estate-wide state file — state is partitioned per environment-subscription and per root so a mistake's blast radius is one root. Roots share data through published outputs, never by reading each other's raw state, which would re-introduce the coupling ADR 0004 forbids one level up.

### 4.2 Governance, policy, and compliance

**Modules ship their own policy and monitoring (ADR 0003).** A module's directory contains the Azure Policy and the alerts/workbooks/diagnostic settings that govern the resources it produces. A consumer who deploys a module gets its governance automatically, with no separate team in the loop. This is the structural fix for AP-001 and the policy half of AP-009.

**Policy follows an audit-before-deny lifecycle, and exemptions are first-class (ADR 0008).** Every new enforcement starts in `Audit` for 30–90 days; promotion to `Deny` requires evidence from that audit window. Enforcement is tiered — sandbox and dev stay in audit, production denies once the data supports it — except for policies that protect the substrate itself, which deny everywhere from day one. Exemptions are time-boxed, owner-attributed, auditable, and documented. This is the answer to AP-005: scoped, evidence-based policy with a faster exemption path than working around it.

**Tags are a small, mandatory, vocabulary-controlled schema that does real work (ADR 0010).** Five required tags — `owner`, `env`, `cost-center`, `data-classification`, `business-criticality` — with controlled values, enforced by policy. Tags are not decoration: `data-classification=restricted` drives CMK and private endpoints, `owner` drives alert routing, `lifecycle=experimental` drives TTL. A tag that does no work does not exist. This closes AP-008.

**Compliance is a derived control map, not a spreadsheet (ADR 0021).** For a credit union, the NCUA exam and GLBA Safeguards Rule turn on a control map: for each control, what implements it and what evidence proves it operates. Vitruvius makes the mapping *declared structured data* per policy initiative, framework-qualified (`csf:PR.AC-1`, `glba:314.4(c)(1)`), and the bidirectional control map and evidence pack are *generated* from those declarations and checked for drift in CI. A derived map cannot rot. The actual control catalog — which controls are in scope and which policy satisfies each to an examiner's standard — is deliberately left to the security/compliance partners, because inventing it unilaterally produces controls that don't match the organization's risk posture.

### 4.3 Observability and measurement

**OpenTelemetry is the collection format; the backend is configuration (ADR 0002).** All instrumentation emits OTel to a collector that fans out to one or more exporters (Azure Monitor by default, Datadog or any OTLP-compatible backend optionally). Service code never imports a vendor SDK directly. Backend choice becomes a config change, not a fleet-wide migration.

**A centralized substrate with federated curation, and signal parity across environments (ADR 0005).** Centralizing solves fragmentation but risks the dumping ground (AP-002); decentralizing does the reverse. The resolution: one substrate per environment, with mandatory semantic conventions, cardinality budgets, and tiered retention enforced at ingest, and owned dashboards with sunset reviews. Signal parity means identical instrumentation in dev, staging, and prod — only retention differs — so regressions surface before production (AP-011). The rule: if it isn't monitored in staging, it doesn't deploy to production.

**Platform health is measured; DORA is the starting frame (ADR 0013).** The platform produces the four DORA metrics for every workload pattern, sourced from the deployment ledger and the substrate, plus a small set of platform-specific signals (time-to-first-deploy, self-service rate) that measure whether the golden paths actually work. Targets are set *with* stream-aligned teams during onboarding, not declared in advance — targets imposed without the consuming team are either ignored or resented.

**SLOs are a per-workload discipline; the platform provides the framework, not the numbers (ADR 0014).** The platform owns the substrate, the SLI definitions, and the error-budget mechanism; the workload team owns the numeric targets and the error-budget policy. The platform has no business picking 99.9% versus 99.95% for a service it does not operate. This is what turns the substrate's data from a dumping ground into decisions.

### 4.4 Security and change management

**Secrets are ephemeral by default (ADR 0009).** Workload identity (federated OIDC) for AKS, managed identity for first-party Azure services, Service Connector for wiring — no static service-principal credentials anywhere. A static secret is an explicit, documented exception with a checked-in rotation handler and an annual review. This is the structural fix for AP-006: rotation is made unnecessary rather than managed.

**Change management is code; break-glass is documented (ADR 0007).** The pull request *is* the change record: required reviewers for segregation of duties, signed commits, protected branches. CD generates the deployment ledger automatically. Standard changes auto-merge by pattern; emergencies go through break-glass with an automated back-fill PR within 24 hours. Drift detection runs on a schedule. This control set is stronger than CAB ceremony and faster — the answer to both AP-004 and AP-007. The controls are deliberately tool-agnostic.

**The CI/CD architecture: OIDC-federated, plan-gated, with a generated deployment ledger (ADR 0020).** This carries ADR 0007's controls into a pipeline. The deploy identity is OIDC workload-identity federation — no static secrets, the same identity holding least-privilege access to state and the target subscription. Plan runs as a PR check; apply is gated, approved, and promoted per environment. The deployment ledger is generated, not hand-maintained, and is both the audit record and the DORA signal source. A scheduled pipeline detects drift. The controls are load-bearing; the platform under them (Azure DevOps is the reference implementation) is configuration.

### 4.5 Networking and integration

**Service discovery is three concerns with three tools (ADR 0006).** "Service discovery" hides three problems: runtime resolution (Kubernetes DNS plus the managed Istio mesh), cross-boundary contract (Azure API Management as the registry and chokepoint, including a facade fronting the cross-cloud SaaS banking core), and inventory and ownership (Backstage, off the runtime path). Conflating them produces the hand-rolled DNS that ossifies a topology (AP-003).

**Network topology is hub-spoke with default-deny egress and centralized private DNS (ADR 0018).** A platform-owned hub per region holds shared connectivity; workload spokes peer to it and never to each other, so the hub is the chokepoint that makes egress control and segmentation enforceable. All egress is default-deny through a hub firewall with an audited allowlist — the regulated-FS answer to "where can data leave?" Private-link DNS zones are centralized and auto-registered. Address allocation is a discipline (central, non-overlapping, documented); the concrete CIDRs are the adopter's. The hub's outputs are consumed by spokes at the consumer boundary — no networking orchestrator.

### 4.6 Resilience

**Disaster recovery is per-workload; the platform provides the primitives (ADR 0015).** Workload teams declare and own RTO and RPO targets per environment, in conversation with risk and the business; the platform ensures the primitives — geo-redundancy, backup configuration, region-pair semantics, findable backup naming — make those targets achievable. Restore drills are a real annual practice captured in the deployment ledger, because a backup that has never been restored is an unverified hope. The platform does not pick a workload's RTO/RPO; that depends on business impact the platform team doesn't own.

### 4.7 Developer experience and the software catalog

**The software catalog is derived from manifests; Backstage is a view, gated behind triggers (ADR 0016).** Backstage is referenced across the design — as the owner of `metadata.owner`, the inventory layer in ADR 0006 — but standing up the server before there is an estate to catalog is portal-before-platform. So the catalog *contract* is decided now: the estate maps onto Backstage's well-known kinds (Domain, System, Component), and `catalog-info.yaml` is *generated* from the manifests by a pure function, never hand-maintained. Standing up the server is deferred behind explicit triggers — a real estate, a dozen-plus entities across teams, a named operator, demonstrated search demand. Until then, an adopter can point an existing Backstage at the repository and get a populated catalog at zero operating cost.

---

## 5. What is built

The decision layer is matched by a working, tested implementation layer — six modules and a reference composition, all anchored on AVM, all carrying their own policy and monitoring, all covered by `terraform test` and CI.

| Layer | Module | What it provides |
|---|---|---|
| foundation | `naming` | Canonical Azure resource names (pure logic). |
| foundation | `tags` | The tag taxonomy map and the initiative that enforces it. |
| foundation | `diagnostic-settings` | The safety-net initiative routing diagnostic settings to the substrate. |
| foundation | `identity` | Platform-baseline managed identities (deploy, policy-remediation). |
| platform-services | `observability-substrate` | The Log Analytics workspace, Application Insights, and alert-routing the estate emits into. |
| workload-patterns | `web-api-aks` | A containerized HTTP API on AKS — workload identity, Key Vault, hardening initiative. |

**The reference composition (`examples/reference-landingzone`)** is the proof that the seams fit. It is a platform landing zone that wires `naming → tags → identity → observability-substrate → diagnostic-settings`, each module's outputs feeding the next at the consumer boundary, with no module importing another. The key seam — the substrate's workspace ID feeding the diagnostic-settings initiative — is the two halves of ADR 0005 connected, demonstrating that the composition story is real rather than asserted.

---

## 6. What is deliberately deferred, and why

The discipline of *not building* is as much a part of the architecture as what is built. Each deferral has a reason and a trigger.

- **The Backstage server** — gated behind a real estate, entity volume, and a named operator. The contract is ready; the product is not yet warranted (ADR 0016).
- **The NCUA/GLBA control catalog** — the *mapping mechanism* is built; the *catalog* is a security/compliance-partner conversation, because controls invented unilaterally don't match the organization's real risk posture (ADR 0021).
- **Concrete topology** — CIDRs, the management-group tree, subscription IDs, regions, firewall SKUs — all are the adopter's, supplied in environment roots, because the real environment is not yet known.
- **The CI/CD platform** — the change-as-code controls are decided; the specific platform is a reference choice, swappable by configuration (ADR 0020).
- **Per-workload targets** — SLO numbers, RTO/RPO, DORA targets — these belong to the workload teams, set in conversation, not declared from the platform (ADRs 0013, 0014, 0015).

A reviewer reading these deferrals learns more about the architecture's judgment than from any module: the design knows the difference between a contract it can fix now and a specific it has no business inventing.

---

## 7. Adoption posture

Vitruvius is taken **whole or in part**. The contracts are designed to be stable seams an adopter binds to; the modules are reference implementations an adopter can use directly or fork. The highest-confidence, infrastructure-independent layer — the manifest contract, the catalog contract, the policy lifecycle, the change-as-code controls, the observability conventions — can be adopted before any concrete topology is known. The concrete layer is supplied as the real environment becomes known, at the consumer boundary, in environment roots like the reference landing zone.

What an adopter needs before going live, beyond the reference foundation: their real ALZ management-group tree and subscriptions, their address allocation, their CI/CD platform binding, the NCUA/GLBA control catalog built with compliance partners, and — when the estate justifies it — the deferred services (the networking hub, the secrets and key-management modules, the Backstage server).

---

## Appendix — Decision index

| ADR | Decision | The wherefore |
|---|---|---|
| 0001 | Terraform, anchored on AVM | Don't re-implement vetted primitives; standardize the IaC substrate. |
| 0002 | Observability is OpenTelemetry-first | Keep backend choice a config change, not a migration. |
| 0003 | Modules ship their own policy and monitoring | Governance is a property of a module, not a later team's project (AP-001). |
| 0004 | Composition by output data; no orchestrators | Keep the estate legible; avoid component sprawl. |
| 0005 | Centralized substrate, federated curation, signal parity | Get centralization without the dumping ground; catch regressions early (AP-002, AP-011). |
| 0006 | Service discovery as three concerns, three tools | Stop conflating runtime, contract, and inventory into ossified DNS (AP-003). |
| 0007 | Change management as code | Stronger and faster than CAB ceremony (AP-004, AP-007). |
| 0008 | Audit-before-deny lifecycle; first-class exemptions | Scoped, evidence-based policy instead of sweeping bans (AP-005). |
| 0009 | Secrets ephemeral by default | Make rotation unnecessary rather than managed (AP-006). |
| 0010 | Small, mandatory, vocabulary-controlled tags | Tags that do real work; cost and policy targeting become possible (AP-008). |
| 0011 | Module manifest as the structured contract | One source of truth for humans, auditors, agents, and the catalog. |
| 0012 | Collaborative design | Opinions formed from practice, not issued as edicts (AP-012). |
| 0013 | Platform health is measured; DORA is the frame | A platform that isn't measured can't be improved or defended. |
| 0014 | SLOs are a per-workload discipline | The platform provides the framework; the team owns the numbers. |
| 0015 | DR is per-workload; the platform provides primitives | Achievable, drilled recovery instead of a binder nobody has read. |
| 0016 | Catalog contract now; Backstage server deferred | Decide the derivation, defer the portal until it's warranted. |
| 0017 | State is per-blast-radius, identity-accessed, sensitive | State holds secrets and is a blast-radius boundary; treat it accordingly. |
| 0018 | Hub-spoke, default-deny egress, central private DNS | Known, audited egress; private resolution; portable topology. |
| 0020 | CI/CD architecture: OIDC, plan-gated, generated ledger | Carry the change-as-code controls into a concrete, secret-free pipeline. |
| 0021 | Compliance control mapping is declared data | A derived, checkable control map that cannot rot. |
| 0024 | Bind to ALZ by role; scopes are a named vocabulary | Attach to any conformant landing zone without owning its hierarchy. |
