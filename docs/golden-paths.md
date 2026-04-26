# Golden Paths Over Gold Cages

The single most important architectural decision in this repo is what to make opinionated and what to leave open. Get this wrong in either direction and the platform fails: too rigid and you paint engineers into corners ([AP-005](./anti-patterns.md#ap-005--sweeping-policy-bans)); too loose and every team reinvents incompatible wheels ([AP-010](./anti-patterns.md#ap-010--no-golden-paths)). The discipline of a good platform is choosing the seam carefully and defending it.

## The two failure modes

| Failure | Symptom |
|---|---|
| **Gold cage** | Sweeping policies, mandatory frameworks, single-vendor monoculture, manager approvals everywhere. Engineers route around the platform via shadow IT, personal subscriptions, or quiet workarounds. |
| **Total freedom** | Every team picks its own auth, logging, retry, deploy shape. Integration is hell. Security gaps proliferate. The platform team is reduced to publishing PowerPoint standards nobody adopts. |

The right answer is neither. The right answer is **opinionated cross-cutting, free intra-app**, with a documented deviation path.

## Defining "cross-cutting"

A **cross-cutting concern** is a property of a system that affects many components but is conceptually orthogonal to the components' core business logic. They are called *cross-cutting* because they cut across the natural decomposition of the system — you cannot put them in any one module because they belong in many.

The term comes from aspect-oriented programming, where it described things like logging, transactions, and security — properties of *how* an application does its work, not *what* the application does. In platform engineering, the same idea scales to infrastructure: cross-cutting concerns are the properties **every workload needs regardless of what the workload is**.

The opposite is an **intra-app concern**: a property unique to a single workload — its language, framework, internal architecture, business logic. The platform has no opinion on these.

The distinction matters because the entire opinion / freedom split below depends on it. Without a clear definition, every architectural request becomes a debate; with one, you can answer *"use the pattern"* or *"you can pick"* with confidence.

### Current cross-cutting concerns in this repo

The manifest schema enumerates exactly six. Each module declares which ones it participates in via `spec.cross_cutting` in its `manifest.yaml`.

| Concern | What it covers | Why it's cross-cutting |
|---|---|---|
| **identity** | Authentication and authorization for service-to-service and human-to-service interactions | Every workload talks to *something*; that something needs to know who's calling. |
| **observability** | Logs, metrics, traces, alerts, dashboards | Every workload should be observable; signals must compose across the estate. |
| **secrets** | Credentials, certificates, signing keys, connection strings | Every workload that touches an external system needs them; rotation cannot be per-team. |
| **networking** | Topology (hub/spoke), private endpoints, egress, DNS, service mesh | Every workload lives somewhere on the network; topology is shared. |
| **naming** | Resource naming convention | Every resource has a name; consistency is a one-team decision. |
| **tagging** | Metadata taxonomy (`owner`, `env`, `cost-center`, `data-classification`, `business-criticality`) | Every resource has metadata; cost reports and policy targeting depend on uniformity. |

This list is intentionally short. Adding a concern to it is a real commitment — it means the platform team owns an opinion across the estate, not just for one workload. Adding a concern goes through ADR.

### Concerns we do *not* yet treat as cross-cutting

Honestly listed gaps — concerns that arguably *should* be cross-cutting but aren't yet because the team has not formed a crisp opinion:

- **Cost / FinOps.** Every workload costs money; budget allocation, anomaly detection, and chargeback are cross-cutting in principle. Not yet on the list because tooling and ownership are unsettled.
- **DR / BCP.** Recovery objectives apply to every workload, but no standard yet exists for RTO/RPO bundling against `business-criticality`.
- **Compliance bundling.** The mapping from `business-criticality` and `data-classification` tags to specific control bundles is implied but not first-class.
- **Deployment ledger / provenance.** [ADR 0007](decisions/0007-change-as-code.md) mentions it as part of change-as-code; it could plausibly be a seventh first-class cross-cutting concern. The case has not yet been made.

These graduate to cross-cutting concerns when the team forms a crisp opinion. Adding them prematurely would be its own anti-pattern — opinionating without evidence.

## What's opinionated (cross-cutting concerns — these are law)

These concerns affect every workload, every audit, and every cross-team interaction. The platform has one opinion per concern, expressed as a module or a policy. Teams consume them; they do not reinvent them.

- **Identity** — managed identity / workload identity for service-to-service auth; Entra ID for human auth. No static credentials unless documented exception ([ADR 0009](./decisions/0009-secrets-ephemeral-by-default.md)).
- **Observability** — OpenTelemetry collection format; central substrate; semantic conventions; signal parity across environments ([ADR 0002](./decisions/0002-observability-otel-first.md), [ADR 0005](./decisions/0005-observability-substrate-and-signal-parity.md)).
- **Secrets** — Key Vault as the only store; rotation handlers checked in; access auditable.
- **Networking** — hub-spoke topology; private endpoints by default; egress through known points.
- **Naming** — `modules/foundation/naming` is the only authority on resource names.
- **Tagging** — small required tag set, vocabulary-controlled ([ADR 0010](./decisions/0010-tag-taxonomy.md)).
- **Service contracts** — APIM for cross-boundary; mesh for in-cluster; Backstage for inventory ([ADR 0006](./decisions/0006-service-discovery-three-layers.md)).
- **Change management** — PR-based, signed commits, deployment ledger from CI/CD ([ADR 0007](./decisions/0007-change-as-code.md)).
- **Policy lifecycle** — Audit-before-Deny; exemptions are first-class ([ADR 0008](./decisions/0008-audit-before-deny-policy-lifecycle.md)).

These are not negotiable per-team. They are not options. They are the conditions of being on the platform.

## What's free (intra-app concerns — engineers pick)

These concerns affect one workload's internals. Engineering judgment lives here. The platform has no opinion.

- **Language** — within a documented short list of supported runtimes (typically 3–5).
- **Framework** — within a language; pick what fits the workload.
- **Database engine** — within the supported managed-service catalog.
- **Internal architecture** — modular monolith vs. microservices; sync vs. async; whatever fits the problem.
- **Test framework, CI tooling within the pipeline, branching style, code style** — team's call.
- **Algorithmic and data-modeling choices** — the platform doesn't have an opinion on whether you use a hash map or a B-tree.

Engineers spend their judgment where it matters. The platform spends its opinions where they compound across the estate.

## The contract

Every workload-pattern module in `modules/workload-patterns/` encodes this contract:

> **Use the pattern → all cross-cutting concerns are wired correctly by default.**
> **Deviate from the pattern → you own all the cross-cutting yourself, plus an ADR documenting why.**

This is the golden path. It is not gold-plated; it is just well-paved enough that almost no one chooses to leave it. When someone does leave it — for good reason — the deviation is documented, reviewed, and treated as the exception it is. The deviation path exists; it is not free.

## The deviation workflow

A team that needs to deviate from a workload pattern follows a documented process:

1. **Open an ADR in `docs/decisions/`** explaining what is being deviated from, why, and what cross-cutting concerns the team is taking ownership of.
2. **Identify the cross-cutting concerns the team will reimplement.** All of them — not a subset. Identity, observability, secrets, networking conventions, deployment ledger, monitoring, policy compliance.
3. **Show evidence the reimplementation meets the same audit and operational bar** as the pattern's defaults. The platform team reviews; the security team reviews.
4. **Accept ongoing maintenance.** The deviation is now this team's burden. They cannot ask the platform team to retrofit the pattern's improvements onto their fork.

The workflow is faster than building cross-cutting from scratch. By design, the path of least resistance is to use the pattern.

## How this shows up in the repo

- **`modules/workload-patterns/`** is the inventory of golden paths.
- **`modules/foundation/`** and **`modules/platform-services/`** hold the cross-cutting concerns the patterns wire in.
- **`docs/decisions/`** records the deviations and the patterns themselves.
- **`docs/anti-patterns.md`** AP-005 and AP-010 are the two failure modes this principle prevents.

## Why this matters for the team operating the platform

Most of a platform team's day is spent at this seam. Every new request can be answered three ways: *"use the pattern,"* *"we'll add a pattern,"* *"you can deviate, here's the contract."* A platform team that fluently uses all three answers — and resists the pull to either extreme — is the team that compounds. A team that defaults to "no" produces gold cages. A team that defaults to "yes, anything goes" produces wheel reinvention.

This is the single principle the rest of the repo is built around.

## Deviations as signals — a feedback loop, not a failure

Deviation ADRs are read as feedback on the patterns themselves, per [ADR 0012](decisions/0012-collaborative-design.md). A high-deviation pattern means the pattern is wrong, not that the engineers are wrong. The platform team reviews deviation rates quarterly and adjusts patterns accordingly.

This is the antidote to [AP-012 — Seagull architecture](anti-patterns.md#ap-012--seagull-architecture): patterns are not edicts dropped from above, they are working artifacts that the platform improves in response to engineer experience.
