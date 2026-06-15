# pipelines/

The reference ADR 0020 deployment pipeline — the thin vertical slice that connects the ADR 0025 conformance evaluator to a *real* Terraform plan and binds every input that influenced the verdict to one saved plan.

The control logic is vendor-independent (`scripts/pipeline.py` + `scripts/evaluate-conformance.py`); `azure-pipelines-deploy.yml` is only the Azure DevOps orchestration, because ADR 0020 names Azure DevOps as the reference. Another vendor maps the same steps onto its own primitives.

## Control flow

```
plan stage  (checkout)
  terraform init ; terraform plan -out=tfplan ; terraform show -json tfplan > tfplan.json
  pipeline.py gate     validate vitruvius.yaml vs the schema; evaluate the rendered plan.
                       on PASS write plan-manifest.json: SHA-256 of every verdict input plus
                       repository/commit/environment/unit, the gate timestamp, and the exemptions
                       relied on (with expiry). on FAIL: exit non-zero, write no manifest -> stop.
  pipeline.py bundle   stage ONLY {tfplan, tfplan.json, vitruvius.yaml, plan-manifest.json}
  publish the bundle   immutable artifact (no .terraform/, no unrelated root files)

── approval ──  the Environment requires an approver who is not the author (ADR 0007)

apply stage  (checkout the repo at the gate's commit; the orchestration checks the actually
              checked-out commit, git rev-parse HEAD, equals the requested one before verifying)
  download the bundle
  pipeline.py verify   FAIL CLOSED: reject an unsupported/missing manifest_version, missing or
                       unexpected hash keys, missing required fields, a runtime identity
                       (repository/commit/environment/canonical unit) that differs from the
                       manifest, a bundle descriptor or selected profile that differs from the
                       committed one at the pinned commit, any artifact whose hash changed, or a
                       relied-upon exemption now expired.
  terraform init -lockfile=readonly ; terraform apply tfplan   (the verified saved plan; no re-plan)
  pipeline.py receipt  emitted for every handled verify/apply outcome (always())
  publish the receipt  (always())
```

## What the manifest binds (the verdict inputs)

Eight SHA-256 hashes — the plan and the everything that decided it: `tfplan` (binary), `tfplan.json`, `vitruvius.yaml`, the resolved **profile**, the **evaluator**, the **descriptor schema**, the **exemption registry**, and this **controller** (`pipeline.py`). The exemption registry is bound even though apply does not re-evaluate, because it shaped the original verdict; the manifest also records which exemptions were *relied on* and their expiry, and apply refuses if one has since expired. `verify` re-checks the runtime identity (repository, commit, environment, deployable unit) against the manifest, not merely copies it forward.

**Descriptor and profile selection are git-anchored.** The manifest is unsigned, so a swapped bundle descriptor could otherwise select a weaker existing profile and carry that profile's valid hash forward. `verify` therefore reads the descriptor committed at the pinned commit (`<unit>/vitruvius.yaml`), requires the bundle descriptor to equal it byte-for-byte, requires the manifest profile to equal the committed descriptor's profile, and resolves the profile file to hash from that committed descriptor — never solely from the unsigned manifest. The deployable unit is canonicalized to one confined repo-relative path (absolute paths, `..` traversal, and anything resolving outside the repo are refused), so `repository + commit + canonical unit` is a stable identity used identically at plan and apply.

## The guarantee — stated precisely

This is **not** "exactly once." It is: **one saved plan, one normal-path apply invocation, and no re-plan between gate and apply.** Within one pipeline run, the plan that was gated and approved is the plan that applies (`terraform apply tfplan` of the verified binary, `init -lockfile=readonly` so provider selection cannot drift). Idempotency under retries/cancellation is Terraform's and the operator's concern, not a claim of this slice.

## How this reconciles ADR 0020

A pre-merge PR plan is **early feedback**. The **deployment plan** is the authoritative, environment-bound, hash-bound gate. The receipt and artifact bundle are **integrity-checked, not signed provenance**. A Terraform plan is bound to one state + input set, so each environment plans, gates, and applies its own plan.

## Artifact handling (sensitive)

Both `tfplan` (binary) and `tfplan.json` can contain sensitive values (resource attributes, computed config, occasionally inlined secrets from variables or data). The published bundle therefore requires:

- **Access** — restricted to the pipeline's service identity and the named approvers; not world/org-readable.
- **Encryption** — at rest (the artifact store) and in transit (TLS); the default for Azure DevOps Pipeline Artifacts, to be confirmed by the adopter.
- **Retention** — short, just long enough to cover the approval window plus audit (e.g., 30 days), then auto-expire.
- **Deletion** — bundles expire on the retention policy; do not pin plan artifacts indefinitely. The durable record is the receipt, not the plan.

## Security limitations of the reference implementation

- **No live execution here.** CI has no Azure credentials, so the slice is proven against committed fixtures, not a live apply.
- **Integrity, not provenance.** SHA-256 over the verdict inputs detects tampering between gate and apply, and descriptor/profile selection is anchored to git (above), so a swapped descriptor or profile is caught. But the manifest is *not* signed and travels in the same bundle it attests: a coordinated replacement of both the bundle and its manifest remains possible until artifact signing / an out-of-band anchor is added — deliberately out of this slice. The receipt is likewise integrity-checked, not signed provenance.
- **Approver identity.** Azure DevOps does not expose the approving identity as a first-class pipeline variable; the receipt's `approver` is sourced from an org-wired `$(APPROVER)` (or the Environment approval API) — only as trustworthy as that wiring.
- **Trust boundary.** The gate trusts the plan JSON Terraform produced; a compromised plan-producing agent is out of scope (the managed-only, fail-closed evaluation bounds but does not eliminate this).

## Fixtures

`scripts/conformance/fixtures/plan.real-shape.json` is a **representative Terraform-plan-shape fixture** — hand-authored, structurally faithful to `terraform show -json` (nested `child_modules`, `mode`, `resource_changes`), used as a compatibility check. It is **not** a Terraform-generated plan; producing one needs Azure credentials and a provider download unavailable in this environment. The other fixtures are synthetic edge cases.
