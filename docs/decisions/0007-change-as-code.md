---
id: 7
title: Change management as code; break-glass is documented
status: accepted
date: 2026-04-26
categories: [process, security, governance]
supersedes: []
superseded_by: []
cites_anti_patterns: [AP-004, AP-007]
cites_adrs: [ADR-0001, ADR-0013]
---

# ADR 0007 — Change management as code; break-glass is documented

## Context

Two failure modes shape this decision:

- [AP-004 — Configuration drift](../anti-patterns.md#ap-004--configuration-drift) — people fix things by hand in the Azure portal; the manual changes pile up; the Terraform code no longer matches reality; and the knowledge of what was changed, and why, leaves when the person who did it leaves.
- [AP-007 — Change-management theater](../anti-patterns.md#ap-007--change-management-theater) — the old-style weekly approval meeting (a **CAB**, or Change Advisory Board, from the ITIL process framework) consumes weeks of approvals while emergency changes bypass it entirely — so the controls don't apply exactly where they are needed most.

The regulatory frame — NCUA examination standards and GLBA safeguards obligations — expects documented authorization, segregation of duties (the person who writes a change is not the one who approves it), change records, and traceability. Regulators specify *outcomes*, not weekly meetings. Modern engineering tooling satisfies those outcomes with greater fidelity than CAB-based processes.

## Decision

Change management is expressed as code, with the same audit-grade rigor as production code. The control set:

### 1. Production human RBAC is read-only by default

**RBAC** (role-based access control) is the system deciding who may do what; by default, humans may only *look at* production. Changes go through a **pull request** (PR — a proposed code change that others review before it merges) to the infrastructure-as-code repo. Production write access is granted just-in-time via **Privileged Identity Management (PIM)** — Azure's "check out admin rights temporarily, with a logged reason and a time limit" feature. A PIM elevation is itself an audit event.

### 2. PR is the change record

- **Required reviewers**, configured via `CODEOWNERS` (a file mapping each part of the repo to its responsible reviewers), provide segregation of duties.
- **Signed commits** prove who really authored a change (gpg or sigstore-equivalent signing).
- **Protected branches** prevent bypassing review; force-push (rewriting history) is disabled.
- **The PR description** is the change description — what, why, blast radius (what could be affected), and how to roll back.

### 3. CD is the change executor

**CD** (continuous deployment — the automated system that ships approved changes) writes the **deployment ledger** automatically: PR link, artifact hash (a fingerprint of exactly what was deployed), target environment, executor identity, timestamp. The ledger is the audit artifact. Humans do not maintain it.

### 4. Standard / normal / emergency classification is encoded in PR labels

- **Standard changes** match a pre-approved pattern (e.g., dependency bumps under semver-patch, scaling parameter changes within bounds) and auto-merge once CI passes. The pattern definitions are themselves code in this repo.
- **Normal changes** require human review per CODEOWNERS.
- **Emergency changes** go through break-glass.

### 5. Break-glass with auto-PR-back

**Break-glass** is the explicitly-allowed emergency path: a PIM elevation used to make a manual change. When that happens, automated diff capture generates a Terraform back-fill PR within 24 hours, folding the manual fix back into code. The emergency change is *captured*, not *forbidden* — forbidding it would push it underground, which is exactly the failure mode CAB processes produce. The back-fill PR contains the diff, the elevation reason, and the executor; review is mandatory before the next deploy.

### 6. Drift detection in CI

A scheduled `terraform plan` (a dry run comparing the code against real production) opens a ticket if it finds any difference. Drift cannot accumulate silently. Each drift ticket is triaged to one of: (a) a bug in the code, (b) a missed back-fill from break-glass, (c) an external party changing things — each handled differently.

> **In plain terms:** the code review *is* the approval, and the system keeps the receipts automatically. Emergencies aren't banned — banning them only hides them — they're allowed, logged, and always written back into the official record.

## What this does not decide

- **The CI/CD platform** — GitHub vs Azure DevOps. The control set is described in GitHub vocabulary but is explicitly tool-agnostic; see §"Tool-platform portability" below for the equivalence table. The platform choice is configuration.
- **The standard-change pattern definitions** — which changes auto-merge is a code-defined set that starts conservative and expands on incident-free history, not a list fixed here.
- **The deployment-ledger and auto-PR-back implementations** — the *requirement* (a generated, audit-grade ledger; break-glass captured within 24h) is decided; the mechanism is a follow-up (the CI/CD architecture work).
- **The commit-signing mechanism** — gpg vs sigstore-equivalent; identity proof is required, the specific tool is not.

## Reversibility

- **The CI/CD platform is cheap to change (two-way door)** — and the ADR is built that way: §"Tool-platform portability" maps every control to its GitHub and Azure DevOps equivalent. Porting is configuration, not architecture.
- **The change-as-code *discipline* is load-bearing (one-way door)** in the sense that matters here: it *is* the audit-control posture. Reversing it (back to CAB-style ceremony, or to untracked manual change) doesn't destroy data, but it dismantles the evidence story examiners rely on and the signals built on it — the deployment ledger feeds the DORA delivery metrics in ADR 0013, and drift detection depends on the plan output being the source of truth. The commitment is to the *controls*; the tools underneath them are swappable.

## Consequences

**Positive.**

- Audit evidence is stronger than a CAB's: PR record, signed commits, CI artifacts, deployment ledger, drift detection, break-glass capture.
- Velocity is higher; standard changes flow without meetings.
- Emergency changes have a documented, codified path; the break-glass is itself part of the audit trail.
- Institutional knowledge is captured in PR descriptions and ADRs, not in retired engineers' memories.
- Segregation of duties is provably enforced (author ≠ approver; the CD pipeline deploys, not a developer's machine).

**Negative — and accepted.**

- The team must invest in tooling: auto-PR-back from PIM, drift detection, the deployment-ledger generator, the standard-change pattern matcher. These are one-time builds with ongoing maintenance.
- Some auditors and managers expect CAB-style ceremony. We provide equivalent (and stronger) evidence in a different form and explain it. This is a communication cost, not a controls cost.
- Standard-change auto-merge requires careful pattern definition. We start the pattern set conservative and expand based on incident-free history.

## Tool-platform portability — GitHub or Azure DevOps

The control set above is described in GitHub vocabulary (PR, CODEOWNERS, GitHub Actions, branch protection). The same controls have direct equivalents in Azure DevOps. **The architectural decision is tool-agnostic; the platform choice is configuration.**

| Concept | GitHub | Azure DevOps |
|---|---|---|
| Source control | GitHub Repos | Azure Repos (Git) |
| Pull request | GitHub PR | Azure Repos PR |
| Required reviewers | `CODEOWNERS` | Branch Policies → Required Reviewers (per-path) |
| Protected branches | Branch protection rules | Branch Policies (build validation, status checks, no direct push) |
| Signed commits | gpg / sigstore | gpg verification via Azure Repos commit policy |
| CI/CD | GitHub Actions | Azure Pipelines (YAML) |
| Standard / normal / emergency labels | PR labels + Actions | PR tags + Pipeline conditional stages |
| Scheduled drift detection | scheduled GitHub Action | scheduled Azure Pipeline |
| Deployment ledger | Actions logs + custom artifacts | Pipelines run history + custom outputs |
| Discussion / issue tracking | GitHub Issues + Discussions | Azure Boards |
| Docs portal | Docs in repo + GitHub Pages | Docs in repo + Azure DevOps Wiki (sourced from repo) |

The choice between platforms is a separate decision driven by org standards, existing tooling integration, and team preference. Both authenticate via Entra ID (Azure's identity service); both support the merge-record-and-deployment-ledger discipline this ADR requires. The ADR's controls hold either way.

Examples and references in this repo currently use GitHub vocabulary because the repo is hosted on GitHub. Porting the active CI artifacts to Azure DevOps is configuration, not architecture — the same `terraform fmt / validate / test` jobs, manifest schema validation, and ADR-index regeneration apply unchanged.

## Cites

- [AP-004](../anti-patterns.md#ap-004--configuration-drift) — drift detection + break-glass with auto-PR-back.
- [AP-007](../anti-patterns.md#ap-007--change-management-theater) — change-as-code as the modern alternative to CAB.
- [ADR 0001](./0001-iac-terraform-with-avm.md) — the IaC substrate this ADR depends on.
