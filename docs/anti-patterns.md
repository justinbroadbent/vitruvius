# Anti-Patterns

The failure modes this repo's design is built to prevent. Each entry names the pattern, explains the conditions that produce it, the cost when it lands, and the specific design choices in this repo that block it. Principles, ADRs, and module conventions cite these entries by ID.

These are not theoretical. They are patterns experienced engineers have watched fail across estates, vendors, and teams. The repo's discipline is the sum of avoiding each of them deliberately.

A note on tense: each "What we do instead" states the *designed posture* — the approach the cited ADRs commit to. Some of its machinery (the OTel collector, scheduled drift detection, performance-budget gates, PIM back-fill automation) is decided but not yet built. [`docs/principles.md`](principles.md) § "How these are enforced" tracks which automated gates are live today; do not cite an entry here as evidence that a control is operating.

---

## AP-001 — Bolted-on monitoring

**What you see.** A separate monitoring or SRE team owns dashboards, alerts, and diagnostic settings, and adds them to workloads after they ship. Workloads are deployed before the monitoring stack catches up. Dashboards refer to fields and resources that have since been renamed or deleted. Alerts page on metrics nobody understands. New services launch with no telemetry at all until the monitoring team gets to them three sprints later.

**Why it happens.** The org chart shapes the architecture. Splitting "build" and "observe" into separate teams creates an interface that drifts.

**What it costs.** Long mean time to detection. Alert fatigue once the monitoring team finally adds alerts. Audit findings for unobserved resources. A learned helplessness where engineers stop trusting the monitoring stack.

**What we do instead.** Modules ship their own diagnostic settings, alerts, workbooks, and dashboards alongside the Terraform that produces the resources they describe — alerts as inline Terraform, workbook/dashboard JSON in `monitoring/`, all named in the manifest (ADR 0003). There is no separate monitoring team authoring per-resource artifacts.

**Cited by:** ADR 0003, ADR 0005, `AGENTS.md` Hard Rule 1.

---

## AP-002 — Telemetry dumping ground

**What you see.** Every service emits everything to one centralized backend. Datadog or Application Insights cost climbs month over month, but answers to operational questions get harder to find. Dashboards proliferate; ownership of any given dashboard is unclear; nobody dares delete one. High-cardinality tags (`member_id`, `request_id` as labels) appear without review. Cost surprises trigger reactive cardinality bans that break running queries.

**Why it happens.** Centralization is treated as the goal rather than as a substrate that requires curation. Without semantic conventions, retention tiers, and cardinality budgets, the centralized backend becomes a bog.

**What it costs.** Six- and seven-figure annual telemetry bills for telemetry nobody reads. Operational questions take longer to answer than they did with a smaller stack. Teams build private mini-stacks because the official one is unusable, and now you have neither centralization nor curation.

**What we do instead.** Centralized substrate, federated curation. OTel semantic conventions are mandatory; cardinality budgets are enforced at the collector; retention is tiered (hot / warm / cold); dashboards have owners and quarterly sunset reviews.

**Cited by:** ADR 0005.

---

## AP-003 — Hard-coded service endpoints

**What you see.** Service A calls Service B by a DNS name baked into Service A's environment configuration. When B moves, every consumer needs an environment update and a redeploy. New services don't appear anywhere discoverable; finding the right team to call requires asking around. Lifecycle events (rename, region migration, deprecation) become months-long projects.

**Why it happens.** Service discovery is treated as a single concern when it is actually three: runtime resolution, cross-boundary contract, and inventory. Each has a different right-tool answer. Conflating them produces hand-rolled DNS plumbing that ossifies the topology.

**What it costs.** Every cross-service change becomes a cross-team change. New services have no front door. The org cannot move services across regions, clouds, or runtime environments without a project.

**What we do instead.** Three explicit layers, each with its own tool: AKS DNS plus the managed-Istio service-mesh add-on for in-cluster runtime resolution; Azure API Management as the cross-boundary contract registry (every published API has a stable URL, OpenAPI definition, and observability story); Backstage as the inventory and ownership catalog. Connection wiring uses managed identity plus Service Connector — endpoints and credentials are not in env vars.

**Cited by:** ADR 0006.

---

## AP-004 — Configuration drift

**What you see.** Someone changes a resource in the portal because Terraform is broken or because it's faster. Months later, `terraform plan` shows hundreds of changes, half of them destructive. The original change-maker has left the team; nobody can explain why the change was made.

**Why it happens.** Manual changes are forbidden but possible. There is no automated drift detection and no path to capture an emergency change back into code. The path of least resistance is the portal.

**What it costs.** Terraform becomes untrusted. Engineers stop running plan. Drift accumulates until a forced migration or audit reveals it. Tribal knowledge dies with departures.

**What we do instead.** RBAC locks production to read-only for humans by default; change goes through PR. Privileged Identity Management (PIM) with just-in-time elevation is the only way to make a manual change, and elevation generates a Terraform back-fill PR within 24 hours. CI runs scheduled drift detection; non-zero plans open tickets. ADRs are the durable record of non-obvious changes.

**Cited by:** ADR 0007.

---

## AP-005 — Sweeping policy bans

**What you see.** A policy is published that bans an entire resource type or configuration shape ("no VMs," "no public IPs anywhere"). Engineers hit the ban during legitimate experimentation. There is no exemption path, or the exemption path requires multi-week approval. Engineers route around the policy via shadow IT or simply give up.

**Why it happens.** Security and platform teams treat policy as binary — allow or deny. The cost of a careful, scoped, audited policy is higher than the cost of an overbroad one for the *team writing it*, but lower for everyone consuming it. The incentive is misaligned.

**What it costs.** Engineering velocity. Trust in the platform. Real experimentation moves to personal subscriptions and unmanaged accounts — which is the *opposite* of what the policy intended.

**What we do instead.** Audit-before-Deny policy lifecycle: every new policy ships in `Audit` mode for 30–90 days before promotion to `Deny`. Exemptions are a first-class workflow with expiry and justification. Tiered enforcement: sandbox and dev use `Audit`; production uses `Deny`. Policies are grouped into Initiatives, where the *initiative* documents the intent.

**Cited by:** ADR 0008, ADR 0012.

---

## AP-006 — Secret rotation toil

**What you see.** Senior engineers spend hours per quarter rotating certificates and API keys. Rotation procedures live in documents that are out of date by the next rotation. Some secrets are quietly never rotated because rotation breaks downstream services nobody fully understands. Audit discovers a 1,000-day-old secret in production.

**Why it happens.** Static secrets are treated as the default. Rotation is treated as a maintenance task, not as something the platform should make unnecessary. Identity-based authentication exists but is not the path of least resistance.

**What it costs.** Senior engineering time on a low-skill task. Audit findings. Risk of credential leaks because rotation is slow. Outages when a forgotten secret expires.

**What we do instead.** Secrets are ephemeral by default. Workload Identity (federated OIDC) for AKS workloads; managed identity for first-party Azure services; Service Connector for connection wiring. Static secrets are documented exceptions with checked-in rotation handlers — not scripts on someone's laptop. Key Vault diagnostic settings emit access logs to the observability substrate.

**Cited by:** ADR 0009.

---

## AP-007 — Change-management theater

**What you see.** A weekly Change Advisory Board meeting where managers approve changes whose technical content they cannot evaluate. Standard changes routinely take a week to clear. Emergency changes bypass the process — which means the process is not actually load-bearing for the high-risk path. The audit binder grows; outcomes do not improve.

**Why it happens.** ITIL change-management practices were designed for an era of large, infrequent, irreversible deployments. They have not been redesigned for an era of small, frequent, automatable deployments with strong observability and instant rollback.

**What it costs.** Engineering velocity. Approval theater that auditors are no more impressed by than a clean PR record. Worse outcomes than the modern alternative because emergency-path bypasses are the dominant change shape.

**What we do instead.** Change management as code. Pull requests with required reviewers and protected branches *are* the documented authorization record. Signed commits prove identity. CD pipelines auto-generate the change ledger with PR link, artifact hash, environment, approver. Standard changes match a pattern label and auto-approve; normal changes require human review; emergency changes go through break-glass with auto-PR-back. The control set is *stronger* than ITIL CAB and faster.

**Cited by:** ADR 0007, ADR 0012.

---

## AP-008 — Tag chaos

**What you see.** Tags are free-form; the same concept appears as `env=prod`, `Env=Production`, and `environment=PROD`. Cost-by-team reporting is impossible. Policy targeting cannot rely on tags. Some tags are person names; some are `temp` from 2022. Removing a tag breaks something nobody can identify.

**Why it happens.** Tagging is treated as an afterthought rather than as a schema. Without enforcement and a vocabulary, tags accumulate entropy.

**What it costs.** Cost allocation by team or product becomes manual. Lifecycle automation (cleanup of expired experiments) is impossible. Operational tooling cannot use tags as routing keys.

**What we do instead.** A small required tag set with vocabulary-controlled values: `owner`, `env`, `cost-center`, `data-classification`, `business-criticality`. Azure Policy enforces required tags and allowed values, and inherits from resource group via the `modify` effect. Tags do operational work — `data-classification=restricted` triggers CMK and private endpoints; `owner` drives alert routing; `lifecycle=experimental` triggers a 30-day TTL. Tags exist to do work, or they do not exist.

**Cited by:** ADR 0010.

---

## AP-009 — Doc rot

**What you see.** A wiki claims to be the source of truth. Half its links are dead. The answer to today's question is in someone's Slack DM from eighteen months ago. New hires get a "wiki tour" that ends with senior engineers admitting the wiki is mostly wrong.

**Why it happens.** Docs that live far from code are not updated when code changes. There is no failing test for a stale doc. The blast radius of a wrong doc is invisible until it costs an outage or an onboarding week.

**What it costs.** Onboarding velocity. Trust in any documentation, including the docs that are correct. Tribal knowledge that is impossible to audit.

**What we do instead.** Module docs (`README.md`, `AGENTS.md`) live in the module directory. ADRs live in `docs/decisions/`. Module manifests (`manifest.yaml`) provide a structured contract — see [ADR 0011](./decisions/0011-module-manifest.md). Runbooks ship in the `monitoring/` bundle of the module that pages people. Backstage TechDocs surfaces these in a portal by *pulling from the repo* — not by forking the content. If a doc lives in a wiki and the code lives in git, the wiki is wrong on a long enough timeline.

**Cited by:** `AGENTS.md` Hard Rule 8; `docs/principles.md` (venustas); ADR 0011.

---

## AP-010 — No golden paths

**What you see.** Every team picks its own auth library, its own logging format, its own deployment shape, its own retry policy. Three of those implementations have known security holes. Cross-team integration projects spend most of their time bridging incompatible primitives. The platform team's "standards" are PowerPoint, not code.

**Why it happens.** The platform has no opinionated patterns to consume. Without a paved road, every team paves their own. The opposite failure mode of overbroad policy: total freedom produces incompatibility and reinvention instead of corner-painting.

**What it costs.** Security gaps. Integration cost paid every time. Talent attrition because experienced engineers don't want to debug yet another team's bespoke retry-with-jitter implementation.

**What we do instead.** Workload-pattern modules are golden paths, not gold cages. Use the pattern → get all six cross-cutting concerns (identity, observability, secrets, networking, naming, tagging — the canonical list in `docs/golden-paths.md`) for free. Deviate from the pattern → you own the cross-cutting yourself plus an ADR documenting why. The well-paved road is so much easier than the alternative that almost no one deviates.

**Cited by:** `docs/golden-paths.md`, ADR 0012.

---

## AP-011 — Lower-env signal gap

**What you see.** Production is heavily monitored; staging emits a fraction of the signals; dev emits none. A regression introduced in staging is not detected until production traffic exposes it. The on-call engineer rolls back. The post-mortem cites "missing telemetry" — in staging.

**Why it happens.** Telemetry is treated as a production concern. Lower-environment signal volume is cut to save cost. Performance budgets exist as documents, not as CI gates.

**What it costs.** Rollbacks that should have been pre-merge plan-blockers. Production incidents that surfaced in lower envs but were invisible there. Member trust.

**What we do instead.** Signal parity across environments. Same OTel instrumentation everywhere; only retention differs. Synthetic load against staging matched to prod traffic shapes. Performance budgets in CI: deploys that regress p99 latency, error rate, or throughput beyond a threshold are blocked. The rule: if it isn't monitored in staging, it does not deploy to production.

**Cited by:** ADR 0005.

---

## AP-012 — Seagull architecture

**What you see.** An architect (or platform team) designs patterns, policies, and standards in isolation. Decisions arrive as edicts: a new policy goes to `Deny` on day one; a "platform standard" is published in PowerPoint without engineer review; the architect appears at design reviews to issue corrections, then leaves. Engineers route around the platform team because every interaction is corrective, never collaborative. Working from inferred requirements, the architect produces patterns nobody adopts and policies nobody can comply with.

**Why it happens.** Org structure puts the architect in a separate reporting line. Status pressure rewards visible decision-making over visible engagement. The architect's calendar fills with leadership reviews; the engineer's calendar fills with shipping. The two never overlap. The architect's mental model of the system becomes a model of the model — increasingly disconnected from how the system actually behaves under engineer hands.

**What it costs.** Patterns that don't fit real workloads (causes [AP-010](#ap-010--no-golden-paths)). Policies that paint engineers into corners (causes [AP-005](#ap-005--sweeping-policy-bans)). Change processes that are theater rather than control (causes [AP-007](#ap-007--change-management-theater)). Worst of all: the platform team loses credibility, and the broader organization stops believing platform decisions are sound. Recovery from this state takes years, not sprints.

**What we do instead.** Collaborative design as a practiced commitment, encoded in [ADR 0012](./decisions/0012-collaborative-design.md): RFC-style ADRs with sign-off from affected teams; pattern lifecycle (alpha → beta → GA) gated by real adoption, not architect approval; public design surface — no decisions in DMs; embedded rotation through workload teams; office hours where the architect participates as a peer; deviations from patterns read as feedback, not as failures. The architect commits opinions on cross-cutting concerns *based on what they learned from engineers*, not in spite of them. See `CONTRIBUTING.md` for the practical contribution path.

**Cited by:** ADR 0011, ADR 0012, `docs/golden-paths.md`, `CONTRIBUTING.md`.
