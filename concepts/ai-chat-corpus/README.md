# AI Chat over the Repo (RAG)

A small chat interface that answers questions grounded in this repo's content. Users ask in natural language; answers cite the specific files and sections they came from.

**Status:** Concept only. No implementation timeline. Documented here so the design exists if and when a build is funded. See [`concepts/README.md`](../README.md) for the lifecycle of a concept.

---

## Why this, and why now

This repo is dense by design — a substantial citation web of principles, ADRs, anti-patterns, and module contracts. That density is good for engineers immersed in it. It is *not* good for:

- **Stakeholders** (executives, GRC, security, risk) who want to ask one question, not read fifty pages.
- **New engineers** who don't yet know which doc answers their question.
- **Architects** who want to check whether their proposed change conflicts with anything already decided.
- **Auditors** who want grounded answers about a specific control, with citations.

A chat interface targeted at *querying* (not changing) the repo serves all four cases without putting the LLM in the merge path. This is consistent with the team's [AI usage thesis](../../docs/ai-usage.md): AI helps people read and find things; humans still author and approve.

## Prerequisite: why not just Backstage Search?

Backstage Search indexes TechDocs, the catalog, and arbitrary collators; it returns ranked document hits with links. For the *"find me the doc that answers this"* class of question — which is the bulk of stakeholder, new-engineer, and auditor traffic — Backstage Search is sufficient and it costs nothing beyond Backstage itself. If Backstage is being deployed for the catalog, search comes with it.

This concept is only worth building if the team specifically wants generative answers — paraphrased synthesis across multiple documents, structured queries against the manifest index (e.g., *"which experimental ADRs have not been reviewed in 60 days?"*), and natural-language questions that don't map cleanly to a single doc hit. Backstage Search returns hits; this returns answers.

Decision criteria before funding a build:

1. **Is Backstage Search deployed and is its TechDocs index complete for this repo?** If no, do that first. Most of the value is there.
2. **Have we observed real demand for synthesized answers?** If users are happy clicking the top three search hits, generative Q&A is solving a problem nobody has.
3. **Is the structured-query path (manifest index, ADR frontmatter) actually load-bearing for any persona?** The architect-doing-weekly-review query is the strongest case; if architects can answer it from a generated `docs/decisions/README.md` already, the structured-query path doesn't earn its keep either.

If the answers to (2) and (3) are no, the right move is to retire this concept in favor of a Backstage Search configuration writeup, not build it.

## The thesis

A small number of opinionated, well-cited docs is unusually good RAG input. Most corporate wikis are the worst-case input for RAG — stale, fragmented, contradictory, low-density. This repo's structure is the opposite, and the structure is what makes the chat interface viable.

The `manifest.yaml` files are particularly useful: each module's contract, citations, and shipped artifacts in machine-readable form. A retrieval step that surfaces the relevant manifest plus the cited ADR is a higher-quality grounding than a typical document chunk.

## Architecture sketch

API-first: a Go HTTP service is the backend. Multiple clients can hit the same API — a Go CLI ships with v1; a web UI and Backstage plugin are deferred.

```
              ┌──────────────────┐  ┌──────────────────┐
              │  CLI client      │  │  Web UI (htmx)   │
              │  (Go, single bin)│  │  (deferred)      │
              └────────┬─────────┘  └────────┬─────────┘
                       │                     │
                       └──────────┬──────────┘
                                  │ HTTPS / Entra ID
                                  ▼
                        ┌──────────────────┐
                        │  Go HTTP service │
                        │  (stdlib + Azure │
                        │   + Anthropic SDK│
                        └─────────┬────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
     ┌────────────────┐ ┌──────────────────┐ ┌──────────────────┐
     │  Vector store  │ │  Manifest index  │ │  Anthropic API   │
     │  (Azure AI     │ │  (typed JSON,    │ │  (Claude)        │
     │   Search +     │ │   structured     │ └──────────────────┘
     │   embeddings)  │ │   query path)    │
     └────────┬───────┘ └──────────────────┘
              │
              ▼
     ┌────────────────┐
     │  Repo content  │
     │  /docs         │
     │  manifest.yaml │
     │  module READMEs│
     └────────────────┘
```

**Why Go.** Per the team's language preference, software tools are written in Go: single static binary, small image, fast cold start, tight dependency tree, audit-friendly supply chain (go.sum hashes; vendoring available). Stdlib `net/http` for the server; the official Anthropic Go SDK and Azure SDK for Go for the backend integrations.

### Ingestion

A small Go ingestion tool runs on a schedule (CI cron) and ingests:

- `/docs/*.md` — chunked by H2 section.
- `/docs/decisions/*.md` — chunked per ADR section; YAML frontmatter parsed and indexed separately as structured fields.
- Module `manifest.yaml` files — indexed as structured records (no chunking).
- Module `README.md` and `AGENTS.md` — chunked.

Chunks are embedded (Azure OpenAI `text-embedding-3-small` or equivalent) and stored in **Azure AI Search** with metadata: filename, section, type (`adr | anti-pattern | manifest | principle | other`), frontmatter fields, last-modified.

The structured manifest index is a separate retrieval path. Queries like *"which modules cite AP-005?"* answer via structured query, not similarity search.

### Retrieval

Two-track:

1. **Similarity search** over embedded chunks for natural-language queries.
2. **Structured filter** over the manifest / frontmatter index for queries with structured intent (cites, status, area, owner).

A small router prompt classifies the query and decides which path(s) to use. Both can run in parallel; the generation step weighs both retrievals.

### Generation

Claude (Anthropic API) receives:

- The user's question.
- The retrieved chunks plus structured records.
- A system prompt requiring citations and refusing to answer beyond the corpus (no hallucinated docs, no guesses).

Output includes inline citations to specific files and sections. The UI renders them as links into the GitHub repo.

### Clients

API-first design. v1 ships:

- A **Go HTTP service** as the backend, exposing a JSON API for queries and Server-Sent Events for streaming responses.
- A **Go CLI client** (`vitruvius-ask "your question"`) as the primary interface for engineers. Single binary; no Python, Node, or other toolchain required to use it.

Web UI and Backstage plugin are deliberately deferred.

When stakeholders need browser access (v2), the natural shape is **server-rendered HTML with htmx** — keeps the toolchain minimal (no build step, no JS framework, no node_modules). A **Backstage plugin** is a v3 path if Backstage adoption progresses, hitting the same backend API.

The API-first split means one backend serves CLI, web, Backstage, or future ChatOps integrations (Slack, Teams) without a rewrite.

### Deployment

- **Single Go binary** (~30–50 MB image). Smaller image, faster cold start, fewer transitive dependencies than a Python or Node container — which matters for both audit and Container App scale-from-zero behavior.
- Runs as an Azure Container App (preferred) or App Service. Workload-pattern modules wire either trivially.
- Authenticated via Entra ID; private to the org.
- All conversations logged to the observability substrate (per [ADR 0005](../../docs/decisions/0005-observability-substrate-and-signal-parity.md)) for audit and quality tuning.
- No conversation logs leave the org boundary.
- Dependencies vendored or pinned via `go.sum` for fully reproducible builds.

## Corpus content (what's in, what's out)

### In

- All `/docs/*.md`
- All `/docs/decisions/*.md` (ADRs)
- All module `manifest.yaml`
- All module `README.md` and `AGENTS.md`
- `schemas/module-manifest.schema.json` — so the bot can answer *"what's in a manifest?"*
- `CONTRIBUTING.md`
- The `AGENTS.md` at the repo root

### Out

- Application source code — out of scope; engineers go to the code itself.
- Production telemetry — out of scope; that's the observability substrate.
- Member data — categorically out.
- Discussions in PR comments — conclusions are in the merged docs; the discussions are working artifacts, not knowledge artifacts.
- The Slack archive — would dilute corpus quality with unstructured chatter.

The discipline of *"only what's in the merged repo"* is a feature: it forces decisions to be captured in docs, which is the same discipline this repo already enforces (per [AP-009](../../docs/anti-patterns.md#ap-009--doc-rot)).

## Example queries

**Stakeholder / exec:**
> *"What's our position on using AI for member-facing decisions?"*

Expected: retrieves [`docs/ai-usage.md`](../../docs/ai-usage.md) § "Where we do NOT use AI" and quotes the relevant section verbatim with a link.

**New engineer:**
> *"I need to deploy a web API on AKS. What should I follow?"*

Expected: retrieves `docs/golden-paths.md` and the (forthcoming) `modules/workload-patterns/web-api-aks/manifest.yaml` and `README.md`. Surfaces the contract: *use the pattern → all cross-cutting handled.*

**Architect checking intent:**
> *"Are there any anti-patterns about consolidating monitoring teams?"*

Expected: retrieves [AP-001](../../docs/anti-patterns.md#ap-001--bolted-on-monitoring) and [AP-002](../../docs/anti-patterns.md#ap-002--telemetry-dumping-ground), plus the relevant ADR 0003 / 0005 sections.

**Auditor:**
> *"How does this platform handle change-management for production deployments?"*

Expected: retrieves [ADR 0007](../../docs/decisions/0007-change-as-code.md) and surfaces the deployment-ledger and break-glass-with-auto-PR-back paragraphs as structured evidence.

**Architect doing weekly review:**
> *"Which experimental ADRs have not been reviewed in 60 days?"*

Expected: structured query over frontmatter; returns a list, not prose. (This is where the structured-query path matters; similarity search would be useless here.)

## What this is NOT

- **Not a path-of-action.** The bot does not open PRs, change configuration, or modify the repo.
- **Not a replacement for reading docs in onboarding.** It supplements; it does not substitute.
- **Not a substitute for the security team, GRC, or counsel** for compliance interpretation.
- **Not a Q&A bot for runtime issues** — that's the observability substrate and on-call runbooks.
- **Not a generic LLM with RAG.** It is grounded in *this* corpus, refuses to answer outside it, and is tuned for the four user personas above.

## Cost and complexity (rough)

| Dimension | Estimate |
|---|---|
| Embedding cost (full reindex) | ~$0.02 at current OpenAI prices for ~500KB of markdown; negligible. |
| Storage | Azure AI Search lowest tier sufficient (low-tens-of-thousands of chunks). |
| Compute | Go binary container ~30–50 MB image; ~64 MB RAM at idle in Container Apps; sub-second cold start. |
| API cost per conversation | $0.05–$0.20 (Sonnet for routine; Opus for complex audit-grade questions). |
| Build effort | v1 in 3–5 days for someone fluent in Go + Azure AI Search; longer if learning either. |

## Open questions (for the build conversation, not now)

- Vector store choice: Azure AI Search vs. pgvector on PostgreSQL vs. a managed vendor. Azure AI Search is the natural Azure-first answer; pgvector is cheaper at small scale.
- Embedding model: Azure OpenAI vs. local sentence-transformers. Local is cheaper but requires a model-hosting decision.
- Update cadence: real-time on push vs. nightly batch. Nightly is sufficient for v1; real-time is later.
- Conversation memory: stateless per-turn vs. session memory. Stateless for v1; session memory adds value but adds privacy/audit considerations.
