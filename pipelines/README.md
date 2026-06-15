# pipelines/

The reference ADR 0020 deployment pipeline — the thin vertical slice that connects the ADR 0025 conformance evaluator to a *real* Terraform plan and binds plan, conformance verdict, approval, and apply to one saved artifact.

The control logic is vendor-independent (`scripts/pipeline.py` + `scripts/evaluate-conformance.py`); `azure-pipelines-deploy.yml` is only the Azure DevOps orchestration, because ADR 0020 names Azure DevOps as the reference. Another vendor maps the same four steps onto its own primitives.

## Control flow: plan → apply

```
plan stage
  terraform init
  terraform plan -out=tfplan            # one saved binary plan
  terraform show -json tfplan > tfplan.json
  pipeline.py gate                       # validate vitruvius.yaml; evaluate the rendered plan;
                                         #   on PASS write plan-manifest.json with the SHA-256 of
                                         #   tfplan, tfplan.json, vitruvius.yaml, the resolved profile,
                                         #   the evaluator, plus the source commit.
                                         #   on FAIL: exit non-zero, write no manifest → stop here.
  publish {tfplan, tfplan.json, vitruvius.yaml, plan-manifest.json}   # immutable artifact

── approval ──  Environment requires an approver who is not the author (ADR 0007)

apply stage
  download the artifact
  pipeline.py verify                     # recompute every hash; refuse if any differs from the manifest
  terraform apply tfplan                 # the exact saved plan — there is no second plan
  pipeline.py receipt                     # emit deployment-receipt.json (commit, root, env, profile,
                                         #   artifact hashes, approver, result, applied-at)
  publish deployment-receipt.json
```

Hashes are computed **before** approval (gate) and verified again **before** apply (verify); the apply refuses if any artifact or hash differs. The plan that was gated and approved is the plan that applies.

## How this reconciles ADR 0020

ADR 0020 as first written said conformance is a pre-merge PR check, that apply consumes "the exact plan reviewed," and that "the same built artifact promotes through every environment." For Terraform those can't all hold: a saved plan is bound to one backend/state + input set, so a PR-time plan is not the binary plan applied to each environment when environments differ by input. The authoritative, hash-bound gate therefore runs **inside one environment's pipeline run**, on that environment's own plan. A pre-merge PR check is a useful early signal but is not the hash-bound gate. ADR 0020 has been corrected to say so.

## What is built vs planned

Built (and self-tested in CI, `pipeline.py --self-test`): the gate/verify/receipt control logic, artifact hashing, tamper detection, exact-plan selection, and the reference YAML.

Not built: live execution (needs an Azure DevOps org, an OIDC service connection, and real Azure); the **durable, append-only, queryable ledger service** of ADR 0020 §3 (the receipt is one record, not the service); scheduled drift detection; break-glass reconciliation; and multi-environment promotion orchestration.

## Security limitations of the reference implementation

- **No live execution here.** CI has no Azure credentials, so the slice is proven against committed plan fixtures, not a live apply.
- **Approver identity.** Azure DevOps does not expose the approving identity as a first-class pipeline variable; the receipt's `approver` is sourced from an org-wired `$(APPROVER)` (or the Environment approval API). Until that is wired, the receipt's approver field is only as trustworthy as that wiring.
- **Hashes are integrity, not provenance.** SHA-256 over the artifacts detects tampering between gate and apply within a run; it is not a signature. Signed artifacts / provenance (e.g., a signed manifest) are a future hardening.
- **Trust boundary.** The gate trusts the plan JSON Terraform produced; it does not independently re-derive resource intent. The managed-resource boundary and fail-closed assertions (ADR 0025) bound this, but a compromised plan-producing agent is out of scope for this slice.
