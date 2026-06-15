#!/usr/bin/env python3
"""Vendor-independent control logic for the ADR 0020 deployment-pipeline slice.

This connects the ADR 0025 conformance evaluator to a real Terraform plan and
binds plan, conformance verdict, approval, and apply to ONE saved plan artifact.
The Azure DevOps YAML (pipelines/) is only orchestration; this is the contract.

Subcommands, in pipeline order:

  gate    — validate the root's vitruvius.yaml against the descriptor schema,
            evaluate the rendered plan (tfplan.json) with the existing evaluator,
            and on PASS write plan-manifest.json recording the SHA-256 of every
            artifact (the binary tfplan, tfplan.json, vitruvius.yaml, the resolved
            profile, the evaluator, and the source commit). Exits non-zero — and
            writes no manifest — when conformance fails, so the pipeline stops
            BEFORE approval/apply.
  verify  — recompute every artifact hash and refuse if any differs from the
            manifest. Runs immediately before `terraform apply tfplan`, so the
            plan that was gated and approved is exactly the plan that applies.
  receipt — emit a deployment receipt from the manifest plus approver and result.
  --self-test — exercise hashing, tamper detection, receipt, and exact-plan
            selection against fixtures (CI; no Azure needed).

A real azurerm plan needs Azure credentials, so CI runs the self-test against a
sanitized real-shape plan fixture; live execution belongs to an Azure DevOps org
(see docs/IMPLEMENTATION-STATUS.md).

Exit 0 on success; 1 with one line per finding otherwise.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

REPO = Path(__file__).resolve().parent.parent
EVALUATOR_PATH = REPO / "scripts" / "evaluate-conformance.py"
SCHEMA_PATH = REPO / "schemas" / "conformance-descriptor.schema.json"
PROFILES_DIR = REPO / "profiles"

# The evaluator filename has a hyphen, so load it by path rather than import.
_spec = importlib.util.spec_from_file_location("evaluate_conformance", EVALUATOR_PATH)
ev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ev)

MANIFEST_VERSION = 1


def sha256_file(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def profile_path(profile_ref: str) -> Path:
    return PROFILES_DIR / f"{profile_ref.split('/')[0]}.yaml"


def artifact_hashes(root: Path, profile_ref: str) -> dict:
    return {
        "tfplan": sha256_file(root / "tfplan"),
        "tfplan_json": sha256_file(root / "tfplan.json"),
        "descriptor": sha256_file(root / "vitruvius.yaml"),
        "profile": sha256_file(profile_path(profile_ref)),
        "evaluator": sha256_file(EVALUATOR_PATH),
    }


def cmd_gate(args) -> int:
    root = Path(args.root)
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        desc = ev.validate_descriptor(root / "vitruvius.yaml", schema)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL descriptor invalid: {exc}", file=sys.stderr)
        return 1

    profile_ref = desc["spec"]["profile"]
    plan = json.loads((root / "tfplan.json").read_text(encoding="utf-8"))
    failures, exemption_findings = ev.evaluate(desc, plan, registry=ev.load_registry())
    if failures or exemption_findings:
        for f in failures:
            print(f"FAIL {f['rule']} — {f['resource']}: {f['detail']}", file=sys.stderr)
        for finding in exemption_findings:
            print(f"FAIL exemption — {finding}", file=sys.stderr)
        print(f"\nConformance failed for {profile_ref}; stopping before approval. No manifest written.", file=sys.stderr)
        return 1

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "repository": args.repository,
        "commit": args.commit,
        "environment": args.environment,
        "root": str(root),
        "profile": profile_ref,
        "hashes": artifact_hashes(root, profile_ref),
    }
    Path(args.out).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"OK — plan conforms to {profile_ref}; manifest written to {args.out} "
          f"(tfplan {manifest['hashes']['tfplan'][:12]}…).")
    return 0


def cmd_verify(args) -> int:
    root = Path(args.root)
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    recomputed = artifact_hashes(root, manifest["profile"])
    drift = [k for k, v in manifest["hashes"].items() if recomputed.get(k) != v]
    if drift:
        for k in drift:
            print(f"FAIL artifact '{k}' changed since the gate: manifest {manifest['hashes'][k][:12]}… "
                  f"now {recomputed.get(k, 'absent')[:12] if recomputed.get(k) else 'absent'}…", file=sys.stderr)
        print("\nRefusing to apply — the approved plan is not the plan on disk.", file=sys.stderr)
        return 1
    print(f"OK — all {len(recomputed)} artifacts match the gated manifest; safe to apply the saved tfplan.")
    return 0


def cmd_receipt(args) -> int:
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    receipt = {
        "repository": manifest["repository"],
        "commit": manifest["commit"],
        "root": manifest["root"],
        "environment": manifest["environment"],
        "profile": manifest["profile"],
        "artifact_hashes": manifest["hashes"],
        "approver": args.approver,
        "apply_result": args.apply_result,
        "applied_at": args.applied_at or datetime.now(timezone.utc).isoformat(),
    }
    Path(args.out).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"OK — receipt written to {args.out} ({receipt['apply_result']}, approver {receipt['approver']}).")
    return 0


def self_test() -> list[str]:
    problems: list[str] = []
    fixtures = REPO / "scripts" / "conformance" / "fixtures"
    descriptor = (REPO / "examples" / "workload-onboarding" / "vitruvius.yaml").read_text(encoding="utf-8")

    def stage(plan_fixture: str) -> Path:
        d = Path(tempfile.mkdtemp())
        (d / "tfplan").write_bytes(b"BINARY-PLAN-" + plan_fixture.encode())  # opaque saved plan
        (d / "tfplan.json").write_text((fixtures / plan_fixture).read_text(encoding="utf-8"), encoding="utf-8")
        (d / "vitruvius.yaml").write_text(descriptor, encoding="utf-8")
        return d

    def run(fn, **kw):
        # Suppress the subcommands' own output — the self-test asserts on return
        # codes and files, and some calls are expected to fail loudly.
        with open(os.devnull, "w") as null, contextlib.redirect_stdout(null), contextlib.redirect_stderr(null):
            return fn(argparse.Namespace(**kw))

    # 1. gate on a conformant real-shape plan writes a manifest with all six facts.
    root = stage("plan.real-shape.json")
    out = root / "plan-manifest.json"
    rc = run(cmd_gate, root=str(root), repository="org/vitruvius", commit="abc123", environment="dev", out=str(out))
    if rc != 0 or not out.exists():
        problems.append("gate should pass on the conformant real-shape fixture and write a manifest")
    else:
        man = json.loads(out.read_text())
        for key in ("tfplan", "tfplan_json", "descriptor", "profile", "evaluator"):
            if not man["hashes"].get(key):
                problems.append(f"manifest missing hash for {key}")
        if man["commit"] != "abc123":
            problems.append("manifest must record the source commit")

    # 2. verify passes when nothing changed.
    if run(cmd_verify, root=str(root), manifest=str(out)) != 0:
        problems.append("verify should pass when artifacts are unchanged")

    # 3. tamper detection — the binary plan and the json each fail verify.
    saved = (root / "tfplan").read_bytes()
    (root / "tfplan").write_bytes(saved + b"x")
    if run(cmd_verify, root=str(root), manifest=str(out)) == 0:
        problems.append("verify MUST fail when the binary tfplan is tampered")
    (root / "tfplan").write_bytes(saved)
    pj = (root / "tfplan.json").read_text()
    (root / "tfplan.json").write_text(pj + "\n")
    if run(cmd_verify, root=str(root), manifest=str(out)) == 0:
        problems.append("verify MUST fail when tfplan.json is tampered")
    (root / "tfplan.json").write_text(pj)

    # 4. exact-plan selection: the manifest's tfplan hash is the saved plan's hash.
    man = json.loads(out.read_text())
    if man["hashes"]["tfplan"] != sha256_file(root / "tfplan"):
        problems.append("manifest tfplan hash must equal the saved binary plan's hash (exact-plan selection)")

    # 5. receipt carries the required fields and the manifest's hashes.
    rcpt = root / "deployment-receipt.json"
    run(cmd_receipt, manifest=str(out), approver="reviewer@org", apply_result="success",
        applied_at="2026-06-15T00:00:00+00:00", out=str(rcpt))
    r = json.loads(rcpt.read_text())
    for key in ("repository", "commit", "root", "environment", "profile", "artifact_hashes", "approver", "apply_result", "applied_at"):
        if key not in r:
            problems.append(f"receipt missing field {key}")
    if r.get("artifact_hashes") != man["hashes"]:
        problems.append("receipt hashes must equal the gated manifest's hashes")

    # 6. gate REFUSES (and writes no manifest) on a non-conformant plan.
    bad = stage("plan.regulated-noncompliant.json")
    bad_out = bad / "plan-manifest.json"
    if run(cmd_gate, root=str(bad), repository="org/vitruvius", commit="abc123", environment="dev", out=str(bad_out)) == 0:
        problems.append("gate MUST fail on a non-conformant plan")
    if bad_out.exists():
        problems.append("gate must NOT write a manifest when conformance fails")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd")

    g = sub.add_parser("gate")
    g.add_argument("--root", required=True)
    g.add_argument("--repository", required=True)
    g.add_argument("--commit", required=True)
    g.add_argument("--environment", required=True)
    g.add_argument("--out", required=True)

    v = sub.add_parser("verify")
    v.add_argument("--root", required=True)
    v.add_argument("--manifest", required=True)

    r = sub.add_parser("receipt")
    r.add_argument("--manifest", required=True)
    r.add_argument("--approver", required=True)
    r.add_argument("--apply-result", required=True, dest="apply_result")
    r.add_argument("--applied-at", dest="applied_at", default=None)
    r.add_argument("--out", required=True)

    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        problems = self_test()
        if problems:
            for p in problems:
                print(f"FAIL {p}", file=sys.stderr)
            print(f"\n{len(problems)} finding(s).", file=sys.stderr)
            return 1
        print("OK — gate/verify/receipt hashing, tamper detection, and exact-plan selection all behave.")
        return 0

    return {"gate": cmd_gate, "verify": cmd_verify, "receipt": cmd_receipt}.get(args.cmd, lambda _: ap.error("need a subcommand or --self-test") or 2)(args)


if __name__ == "__main__":
    sys.exit(main())
