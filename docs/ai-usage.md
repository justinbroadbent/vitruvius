# AI Usage on This Platform Team

This document is the team's commitment about how — and how *not* — to use AI. It is a deliberate position, not an aspiration. Reviewed annually and updated as the technology and our experience evolve.

## The thesis

AI is a tool for specific tasks where it has demonstrable advantage over the alternative. It is not infrastructure. It is not autonomous. We use LLMs to accelerate authoring, reading, and pattern-matching — always with humans in the loop, always with the artifacts reviewable in git.

The opposite posture — *"AI is a strategy, find ways to use it"* — produces brittle integrations, audit gaps, and code nobody understands. We avoid it deliberately.

## Where we use AI

### 1. Authoring

Engineers use **GitHub Copilot in VS Code** — the org's procured, IT-managed AI assistant — with the engineer's choice of backing model (Claude, GPT, Gemini, etc., from the models the org's Copilot plan exposes) for:

- Drafting Terraform modules from `manifest.yaml` declarations.
- Drafting ADRs once the Context section is written by a human — the LLM helps *express*; it does not help *decide*.
- Generating monitoring rules and dashboard JSON from intent.
- Translating policy intent into Azure Policy definitions.

Org code, member data, internal documentation, and infrastructure context **never go to AI tools outside the org's procured, contracted set.** That includes personal subscriptions of any kind (CLIs, chat interfaces, free tiers). This is a data-classification rule, not a preference.

No LLM-generated change merges without human review and CI passing.

### 2. Repo Q&A (RAG over the repo)

A chat interface over `/docs`, ADRs, anti-patterns, and module manifests answers natural-language questions:

- *"What's our policy on storing member data?"*
- *"Show me anti-patterns relevant to this PR."*
- *"Which modules are still in `experimental` status?"*
- *"Has anyone already deviated from the AKS pattern?"*

For stakeholders, new engineers, and architects checking their own intent. It is **not** a path-of-action (does not change anything); it is a path-of-knowledge.

See [`concepts/ai-chat-corpus/`](../concepts/ai-chat-corpus/) for the concrete design.

### 3. CI-time pattern matching

*Planned — no such workflow is wired yet (see `docs/principles.md` § How these are enforced).* The intended shape: CI invokes an LLM at PR time to

- match proposed changes against the anti-pattern catalog and surface relevant entries in PR comments,
- suggest which ADRs are most relevant to a given change, and
- flag manifest-vs-code drift the schema validator can't easily express.

Outputs are advisory, attached to the PR for the human reviewer. They do not auto-block or auto-approve.

### 4. Onboarding accelerator

New engineers ask the chat interface their questions instead of waiting for a senior engineer's calendar opening. Senior engineers' time becomes a higher-value resource because the low-skill questions are handled.

## Where we do NOT use AI

### 1. Auto-merge / auto-approve

No pull request merges on the strength of an LLM review — ever. *"The LLM said it looked fine"* is not an approval. (Human-defined standard-change auto-merge — narrow, pre-approved change patterns that merge once deterministic CI passes, per [ADR 0007](decisions/0007-change-as-code.md) — is a separate mechanism and is unaffected: its gate is CI plus a human-authored allowlist, not a model's judgment.)

### 2. Production change execution

Terraform applies, policy promotions, and break-glass operations go through CI/CD with documented human approvals (per [ADR 0007](decisions/0007-change-as-code.md)). An LLM can suggest a change; it does not execute one.

### 3. Member-facing decisions

Credit approval, fraud scoring, member service. These have their own regulatory frame — model risk management, fair-lending, NIST AI RMF. The platform team does not introduce these models. That is a separate conversation with security, risk, and counsel.

### 4. Regulatory or compliance interpretation

An LLM can summarize an ADR. It does not replace counsel, the security team, or auditors. NCUA examiners are real people with real authority; we do not put an LLM between them and the truth.

### 5. As a substitute for good design

AI is good at many things. A confidently-wrong AI-generated design is worse than no design at all. The architect's job is judgment; the LLM's job is leverage. Don't confuse them.

## Why this matters for a regulated environment

NCUA and the broader regulatory landscape are increasingly attentive to AI risk. A platform team that:

- Uses AI deliberately
- Documents the boundaries
- Keeps humans in the merge path
- Maintains auditable artifacts in git

…is better positioned for audit than a team that is enthusiastic but uncritical. The boundaries above are an audit-defensible posture, not a marketing position.

## Tools currently used or planned

| Tool | Use case | Status |
|---|---|---|
| VS Code + GitHub Copilot (model choice: Claude, GPT, Gemini, etc.) | Inline code completion, draft authoring of modules / ADRs / policy / monitoring | Team standard |
| RAG chat over the repo | Stakeholder + engineer Q&A | Concept — see `concepts/ai-chat-corpus/` |
| CI-time LLM checks | PR-time anti-pattern matching, ADR relevance | Planned |

The list will change. The thesis won't.

## Posture matters more than tool choice

The platform team's value is not "we use AI." Every team uses AI now. The value is using it where it pays back, refusing to use it where it doesn't, and keeping the artifacts reviewable in either case. That posture is what separates a serious AI practice from a performative one. The chat interface, the Copilot use, the CI checks — these are evidence of the posture, not the posture itself.

## Review

This document is reviewed every January, or sooner if the technology or our experience materially changes. Material changes go through ADR (next available slot), not direct edits.
