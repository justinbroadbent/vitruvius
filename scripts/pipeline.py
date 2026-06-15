#!/usr/bin/env python3
"""Vendor-independent control logic for the ADR 0020 deployment-pipeline slice.

Connects the ADR 0025 conformance evaluator to a real Terraform plan and binds
every input that influenced the verdict to one saved plan, so the plan that was
gated and approved is the plan that applies. The Azure DevOps YAML (pipelines/)
is only orchestration; this is the contract.

Subcommands, in pipeline order:

  gate    — validate vitruvius.yaml against the descriptor schema, evaluate the
            rendered plan, and on PASS write plan-manifest.json: the SHA-256 of
            every verdict input (tfplan, tfplan.json, vitruvius.yaml, the
            resolved profile, the evaluator, the descriptor schema, the exemption
            registry, this controller), plus repository/commit/environment/unit,
            the gate timestamp, and the exemptions actually relied on (with
            expiry). Exits non-zero and writes nothing when conformance fails.
  bundle  — stage ONLY the artifacts needed downstream (no .terraform/, no
            unrelated root files) for publishing.
  verify  — fail closed: reject an unsupported/missing manifest_version, missing
            or unexpected hash keys, missing required fields, a runtime identity
            (repository/commit/environment/unit) that differs from the manifest,
            any artifact whose hash changed, or a relied-upon exemption that has
            since expired. Runs immediately before `terraform apply tfplan`.
  receipt — emit a deployment receipt for EVERY terminal outcome (verify failed,
            apply not attempted, apply failed, apply succeeded), carrying the
            verify/apply results, exit code, failure phase, and pipeline result.
  --self-test — exercise all of the above against fixtures (CI; no Azure needed).

A real azurerm plan needs Azure credentials, so CI runs the self-test against a
representative Terraform-plan-shape fixture (hand-authored, not Terraform-
generated). Live execution belongs to an Azure DevOps org — see pipelines/README.md.

Exit 0 on success; 1 with one line per finding otherwise.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import hashlib
import importlib.util
import json
import os
import posixpath
import shutil
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path

try:
    import yaml  # noqa: F401  (used transitively via the evaluator)
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

REPO = Path(__file__).resolve().parent.parent
EVALUATOR_PATH = REPO / "scripts" / "evaluate-conformance.py"
PIPELINE_PATH = Path(__file__).resolve()
SCHEMA_PATH = REPO / "schemas" / "conformance-descriptor.schema.json"
REGISTRY_PATH = REPO / "policies" / "conformance-exemptions.yaml"
PROFILES_DIR = REPO / "profiles"

_spec = importlib.util.spec_from_file_location("evaluate_conformance", EVALUATOR_PATH)
ev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ev)

MANIFEST_VERSION = 1
BUNDLE_FILES = ["tfplan", "tfplan.json", "vitruvius.yaml", "plan-manifest.json"]
EXPECTED_HASH_KEYS = {
    "tfplan", "tfplan_json", "descriptor", "profile",
    "evaluator", "schema", "exemptions_registry", "pipeline",
}
REQUIRED_MANIFEST_FIELDS = {
    "manifest_version", "repository", "commit", "environment", "unit",
    "profile", "gated_at", "hashes", "exemptions_used",
}


class PipelineError(Exception):
    pass


def canonical_unit(raw: str) -> str:
    """One canonical repo-relative POSIX path, confined to the repository.

    Rejects absolute paths, traversal, and anything resolving outside the repo,
    so repository + commit + canonical unit is a stable deployable-unit identity.
    """
    if not raw or not raw.strip():
        raise PipelineError("deployable unit is empty")
    p = raw.strip().replace("\\", "/")
    if p.startswith("/") or (len(p) > 1 and p[1] == ":"):
        raise PipelineError(f"deployable unit must be repo-relative, not absolute: {raw!r}")
    norm = posixpath.normpath(p)
    if norm in (".", "") or norm == ".." or norm.startswith("../") or "/../" in norm:
        raise PipelineError(f"deployable unit escapes the repository or is ambiguous: {raw!r}")
    resolved = (REPO / norm).resolve()
    repo = REPO.resolve()
    if resolved != repo and repo not in resolved.parents:
        raise PipelineError(f"deployable unit resolves outside the repository: {raw!r}")
    return norm


def sha256_file(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def profile_path(profile_ref: str) -> Path:
    return PROFILES_DIR / f"{profile_ref.split('/')[0]}.yaml"


def artifact_hashes(root: Path, profile_ref: str) -> dict:
    """Hash every verdict input: the plan/descriptor from the bundle, the control
    files from the repository (checked out at the gate's commit at apply time)."""
    root = Path(root)
    return {
        "tfplan": sha256_file(root / "tfplan"),
        "tfplan_json": sha256_file(root / "tfplan.json"),
        "descriptor": sha256_file(root / "vitruvius.yaml"),
        "profile": sha256_file(profile_path(profile_ref)),
        "evaluator": sha256_file(EVALUATOR_PATH),
        "schema": sha256_file(SCHEMA_PATH),
        "exemptions_registry": sha256_file(REGISTRY_PATH),
        "pipeline": sha256_file(PIPELINE_PATH),
    }


def used_exemptions(descriptor: dict, plan: dict, registry: dict) -> list[dict]:
    """The exemptions the gate actually relied on: those whose rule would have
    failed without them. Recorded with expiry so apply can refuse a stale one."""
    bare = copy.deepcopy(descriptor)
    bare["spec"]["exceptions"] = []
    prewaiver, _ = ev.evaluate(bare, plan, registry=registry)
    failed = {f["rule"] for f in prewaiver}
    out = []
    for exc in descriptor["spec"].get("exceptions", []) or []:
        if exc["rule"] in failed:
            rec = registry.get(exc["exemption"], {})
            out.append({"rule": exc["rule"], "exemption": exc["exemption"], "expires": str(rec.get("expires"))})
    return out


def cmd_gate(args) -> int:
    root = Path(args.root)
    try:
        unit = canonical_unit(args.unit)
    except PipelineError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        desc = ev.validate_descriptor(root / "vitruvius.yaml", schema)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL descriptor invalid: {exc}", file=sys.stderr)
        return 1
    profile_ref = desc["spec"]["profile"]
    plan = json.loads((root / "tfplan.json").read_text(encoding="utf-8"))
    registry = ev.load_registry()
    failures, exemption_findings = ev.evaluate(desc, plan, registry=registry)
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
        "unit": unit,
        "profile": profile_ref,
        "gated_at": datetime.now(timezone.utc).isoformat(),
        "hashes": artifact_hashes(root, profile_ref),
        "exemptions_used": used_exemptions(desc, plan, registry),
    }
    Path(args.out).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"OK — plan conforms to {profile_ref}; manifest written ({len(manifest['hashes'])} hashed inputs, "
          f"{len(manifest['exemptions_used'])} relied-upon exemption(s)).")
    return 0


def cmd_bundle(args) -> int:
    src, dst = Path(args.root), Path(args.out)
    dst.mkdir(parents=True, exist_ok=True)
    for f in BUNDLE_FILES:
        shutil.copy2(src / f, dst / f)
    print(f"OK — staged {len(BUNDLE_FILES)} files to {dst} (excludes .terraform/ and unrelated root files).")
    return 0


def cmd_verify(args) -> int:
    problems: list[str] = []
    try:
        manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL manifest unreadable: {exc}", file=sys.stderr)
        return 1

    if manifest.get("manifest_version") != MANIFEST_VERSION:
        problems.append(f"unsupported or missing manifest_version (got {manifest.get('manifest_version')!r}, expect {MANIFEST_VERSION})")
    for k in sorted(REQUIRED_MANIFEST_FIELDS - set(manifest)):
        problems.append(f"manifest missing required field '{k}'")

    try:
        unit = canonical_unit(args.unit)
    except PipelineError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1

    for field, runtime in [("repository", args.repository), ("commit", args.commit),
                           ("environment", args.environment), ("unit", unit)]:
        if manifest.get(field) != runtime:
            problems.append(f"{field} mismatch: manifest {manifest.get(field)!r} != runtime {runtime!r}")

    # Git-anchor descriptor and profile selection: the bundle descriptor must equal
    # the committed one at the pinned commit, and the profile we resolve comes from
    # the committed descriptor — not solely from the unsigned manifest. Otherwise a
    # replaced bundle could select a weaker existing profile and copy its valid
    # git-anchored hash forward.
    committed_profile = manifest.get("profile")
    committed_desc = REPO / unit / "vitruvius.yaml"
    bundle_desc = Path(args.root) / "vitruvius.yaml"
    if not bundle_desc.exists():
        problems.append("bundle has no vitruvius.yaml descriptor")
    if not committed_desc.exists():
        problems.append(f"no committed descriptor at {unit}/vitruvius.yaml")
    else:
        if bundle_desc.exists() and sha256_file(bundle_desc) != sha256_file(committed_desc):
            problems.append("bundle descriptor differs from the committed descriptor at the pinned commit")
        committed_profile = yaml.safe_load(committed_desc.read_text(encoding="utf-8"))["spec"]["profile"]
        if manifest.get("profile") != committed_profile:
            problems.append(f"manifest profile {manifest.get('profile')!r} != committed descriptor profile {committed_profile!r}")

    hashes = manifest.get("hashes", {})
    keys = set(hashes)
    if keys - EXPECTED_HASH_KEYS:
        problems.append(f"manifest has unexpected hash keys: {sorted(keys - EXPECTED_HASH_KEYS)}")
    for k in sorted(EXPECTED_HASH_KEYS - keys):
        problems.append(f"manifest missing hash key '{k}'")
    if keys == EXPECTED_HASH_KEYS and committed_profile:
        recomputed = artifact_hashes(args.root, committed_profile)  # profile resolved from the committed descriptor
        for k in sorted(EXPECTED_HASH_KEYS):
            if hashes.get(k) != recomputed.get(k):
                problems.append(f"artifact '{k}' changed since the gate")

    today = date.today()
    for ex in manifest.get("exemptions_used", []) or []:
        exp = ex.get("expires")
        if exp and exp != "None":
            try:
                if date.fromisoformat(exp) < today:
                    problems.append(f"relied-upon exemption '{ex.get('exemption')}' (rule {ex.get('rule')}) expired {exp}")
            except ValueError:
                problems.append(f"relied-upon exemption '{ex.get('exemption')}' has an unparseable expiry {exp!r}")

    if problems:
        for p in problems:
            print(f"FAIL {p}", file=sys.stderr)
        print("\nRefusing to apply — the approved verdict inputs are not intact.", file=sys.stderr)
        return 1
    print("OK — manifest version, required fields, runtime identity, all artifact hashes, and exemption validity check out.")
    return 0


def _failure_phase(verify_result: str, apply_attempted: bool, apply_result: str) -> str:
    if verify_result != "success":
        return "verify"
    if not apply_attempted:
        return "pre-apply"
    if apply_result != "success":
        return "apply"
    return "none"


def cmd_receipt(args) -> int:
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    apply_attempted = args.apply_attempted == "true"
    completed_at = args.completed_at or datetime.now(timezone.utc).isoformat()
    apply_succeeded = apply_attempted and args.apply_result == "success"
    try:
        exit_code = int(args.apply_exit_code)
    except (TypeError, ValueError):
        exit_code = None
    receipt = {
        "repository": manifest.get("repository"),
        "commit": manifest.get("commit"),
        "unit": manifest.get("unit"),
        "environment": manifest.get("environment"),
        "profile": manifest.get("profile"),
        "gated_at": manifest.get("gated_at"),
        "artifact_hashes": manifest.get("hashes"),
        "exemptions_used": manifest.get("exemptions_used"),
        "approver": args.approver,
        "verify_result": args.verify_result,
        "apply_attempted": apply_attempted,
        "apply_result": args.apply_result,
        "apply_exit_code": exit_code,
        "failure_phase": _failure_phase(args.verify_result, apply_attempted, args.apply_result),
        "pipeline_result": args.pipeline_result,
        "completed_at": completed_at,
        "applied_at": completed_at if apply_succeeded else None,
    }
    Path(args.out).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"OK — receipt written (phase={receipt['failure_phase']}, verify={args.verify_result}, apply={args.apply_result}).")
    return 0


def contract_test() -> list[str]:
    """Static contract check on the deploy pipeline YAML — orchestration, not runtime.

    The control logic is only safe if the orchestration actually wires it: the
    deploy job must check out the repo before verifying, verify the real commit,
    pin providers with the committed lockfile on both stages, apply the saved plan
    without a second plan, and emit + publish a receipt for every outcome.
    """
    problems: list[str] = []
    path = REPO / "pipelines" / "azure-pipelines-deploy.yml"
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        return [f"deploy pipeline YAML did not parse: {exc}"]

    stages = {s.get("stage"): s for s in doc.get("stages", [])}
    if "plan" not in stages or "apply" not in stages:
        return ["deploy pipeline must have a 'plan' and an 'apply' stage"]

    plan_text = json.dumps(stages["plan"])
    if "init -lockfile=readonly" not in plan_text:
        problems.append("plan stage must run terraform init -lockfile=readonly")
    plan_steps = stages["plan"].get("jobs", [{}])[0].get("steps", [])
    plan_pub = next((s for s in plan_steps if "publish" in s), None)
    if not plan_pub or "bundle" not in str(plan_pub.get("publish", "")):
        problems.append("plan stage must publish only the explicit bundle directory")

    dep = stages["apply"].get("jobs", [{}])[0]
    if "environment" not in dep:
        problems.append("apply must be a deployment job bound to an Environment (non-author approval)")
    try:
        steps = dep["strategy"]["runOnce"]["deploy"]["steps"]
    except (KeyError, TypeError):
        return problems + ["apply deployment job has no runOnce.deploy.steps"]

    texts = [json.dumps(s) for s in steps]
    apply_text = json.dumps(steps)

    def first(substr: str) -> int:
        return next((i for i, t in enumerate(texts) if substr in t), -1)

    co = next((i for i, s in enumerate(steps) if s.get("checkout") == "self"), -1)
    vi, ai, ri = first("pipeline.py verify"), first("terraform apply tfplan"), first("pipeline.py receipt")

    if co < 0:
        problems.append("apply deployment job must check out the repo (checkout: self) for the control files")
    if vi < 0:
        problems.append("apply job must run pipeline.py verify")
    elif co >= 0 and co > vi:
        problems.append("checkout must occur before verification")

    if vi >= 0:
        vt = texts[vi]
        if "git rev-parse HEAD" not in vt:
            problems.append("verify step must check the actual checked-out commit (git rev-parse HEAD)")
        for flag in ("--repository", "--commit", "--environment", "--unit"):
            if flag not in vt:
                problems.append(f"verify step must pass {flag}")

    if "init -lockfile=readonly" not in apply_text:
        problems.append("apply stage must run terraform init -lockfile=readonly")
    if ai < 0:
        problems.append("apply stage must run terraform apply tfplan (the saved plan)")
    if "terraform plan" in apply_text:
        problems.append("apply stage must NOT run a second terraform plan")

    if ri < 0:
        problems.append("apply job must emit a receipt")
    elif steps[ri].get("condition") != "always()":
        problems.append("receipt step must use condition: always()")
    pub = next((s for s in steps if s.get("publish") and "receipt" in json.dumps(s)), None)
    if not pub or pub.get("condition") != "always()":
        problems.append("receipt publication must use condition: always()")

    return problems


def self_test() -> list[str]:
    problems: list[str] = []
    fixtures = REPO / "scripts" / "conformance" / "fixtures"
    descriptor = (REPO / "examples" / "workload-onboarding" / "vitruvius.yaml").read_text(encoding="utf-8")
    ID = dict(repository="org/vitruvius", commit="abc123", environment="dev", unit="examples/workload-onboarding")

    def stage(plan_fixture: str, extra: bool = False) -> Path:
        d = Path(tempfile.mkdtemp())
        (d / "tfplan").write_bytes(b"BINARY-PLAN-" + plan_fixture.encode())
        (d / "tfplan.json").write_text((fixtures / plan_fixture).read_text(encoding="utf-8"), encoding="utf-8")
        (d / "vitruvius.yaml").write_text(descriptor, encoding="utf-8")
        if extra:
            (d / ".terraform").mkdir()
            (d / ".terraform" / "x").write_text("provider")
            (d / "main.tf").write_text("# unrelated")
        return d

    def run(fn, **kw):
        with open(os.devnull, "w") as null, contextlib.redirect_stdout(null), contextlib.redirect_stderr(null):
            return fn(argparse.Namespace(**kw))

    def gate(root, out):
        return run(cmd_gate, root=str(root), out=str(out), **ID)

    def verify(root, manifest, **override):
        ident = {**ID, **override}
        return run(cmd_verify, root=str(root), manifest=str(manifest), **ident)

    def verify_mutated(root, manifest_path, mutate):
        m = json.loads(Path(manifest_path).read_text())
        mutate(m)
        tmp = Path(tempfile.mkdtemp()) / "m.json"
        tmp.write_text(json.dumps(m))
        return verify(root, tmp)

    # gate on a conformant plan writes a complete manifest.
    root = stage("plan.real-shape.json")
    man = root / "plan-manifest.json"
    if gate(root, man) != 0 or not man.exists():
        problems.append("gate should pass on the conformant real-shape fixture and write a manifest")
        return problems
    m = json.loads(man.read_text())
    if set(m["hashes"]) != EXPECTED_HASH_KEYS:
        problems.append(f"manifest must hash exactly {sorted(EXPECTED_HASH_KEYS)}; got {sorted(m['hashes'])}")
    for f in ("gated_at", "exemptions_used", "unit", "repository", "commit", "environment"):
        if f not in m:
            problems.append(f"manifest missing {f}")

    # happy path verify.
    if verify(root, man) != 0:
        problems.append("verify should pass when nothing changed and runtime identity matches")

    # runtime identity mismatches refuse.
    if verify(root, man, commit="WRONG") == 0:
        problems.append("verify MUST refuse a source-commit mismatch")
    if verify(root, man, environment="prod") == 0:
        problems.append("verify MUST refuse an environment mismatch")
    if verify(root, man, unit="examples/other") == 0:
        problems.append("verify MUST refuse a deployable-unit mismatch")

    # fail-closed manifest structure.
    if verify_mutated(root, man, lambda x: x.update(manifest_version=99)) == 0:
        problems.append("verify MUST refuse an unsupported manifest_version")
    if verify_mutated(root, man, lambda x: x["hashes"].pop("schema")) == 0:
        problems.append("verify MUST refuse a missing hash key")
    if verify_mutated(root, man, lambda x: x["hashes"].update(extra="0")) == 0:
        problems.append("verify MUST refuse an unexpected hash key")
    if verify_mutated(root, man, lambda x: x.pop("unit")) == 0:
        problems.append("verify MUST refuse a missing required field")

    # tamper detection for every hashed input (manifest-side and file-side).
    for key in ("schema", "exemptions_registry", "pipeline", "evaluator", "profile", "descriptor", "tfplan_json"):
        if verify_mutated(root, man, lambda x, k=key: x["hashes"].update({k: "0" * 64})) == 0:
            problems.append(f"verify MUST detect a changed '{key}' artifact")
    saved = (root / "tfplan").read_bytes()
    (root / "tfplan").write_bytes(saved + b"x")
    if verify(root, man) == 0:
        problems.append("verify MUST detect a tampered binary tfplan")
    (root / "tfplan").write_bytes(saved)

    # expired relied-upon exemption refused at apply.
    if verify_mutated(root, man, lambda x: x.__setitem__("exemptions_used", [{"rule": "keyvault.no-public-access", "exemption": "EX-OLD", "expires": "2000-01-01"}])) == 0:
        problems.append("verify MUST refuse when a relied-upon exemption has expired")

    # exact-plan selection.
    if m["hashes"]["tfplan"] != sha256_file(root / "tfplan"):
        problems.append("manifest tfplan hash must equal the saved binary plan's hash")

    # bundle stages only the allowed files.
    src = stage("plan.real-shape.json", extra=True)
    run(cmd_gate, root=str(src), out=str(src / "plan-manifest.json"), **ID)
    bundle_out = Path(tempfile.mkdtemp()) / "bundle"
    run(cmd_bundle, root=str(src), out=str(bundle_out))
    if sorted(p.name for p in bundle_out.iterdir()) != sorted(BUNDLE_FILES):
        problems.append(f"bundle must contain exactly {sorted(BUNDLE_FILES)}; got {sorted(p.name for p in bundle_out.iterdir())}")

    # receipt for every terminal outcome.
    def receipt(**kw):
        out = Path(tempfile.mkdtemp()) / "r.json"
        run(cmd_receipt, manifest=str(man), approver="reviewer@org", completed_at="2026-06-15T00:00:00+00:00", out=str(out), **kw)
        return json.loads(out.read_text())

    r_ok = receipt(verify_result="success", apply_attempted="true", apply_result="success", apply_exit_code="0", pipeline_result="Succeeded")
    for k in ("repository", "commit", "unit", "environment", "profile", "artifact_hashes", "approver",
              "verify_result", "apply_attempted", "apply_result", "apply_exit_code", "failure_phase", "pipeline_result", "completed_at"):
        if k not in r_ok:
            problems.append(f"receipt missing field {k}")
    if r_ok["failure_phase"] != "none" or r_ok["artifact_hashes"] != m["hashes"]:
        problems.append("successful receipt must have failure_phase 'none' and the manifest hashes")
    if r_ok.get("applied_at") is None or r_ok.get("completed_at") is None:
        problems.append("a successful receipt must have both completed_at and applied_at")
    r_verify = receipt(verify_result="failed", apply_attempted="false", apply_result="not_attempted", apply_exit_code="-1", pipeline_result="Failed")
    if r_verify["failure_phase"] != "verify" or r_verify.get("applied_at") is not None or r_verify.get("completed_at") is None:
        problems.append("a failed-verify receipt must record failure_phase 'verify', completed_at, and applied_at=null")
    r_fail = receipt(verify_result="success", apply_attempted="true", apply_result="failed", apply_exit_code="1", pipeline_result="Failed")
    if r_fail["failure_phase"] != "apply" or r_fail["apply_exit_code"] != 1 or r_fail.get("applied_at") is not None:
        problems.append("a failed-apply receipt must record failure_phase 'apply', the exit code, and applied_at=null")

    # descriptor / profile must be git-anchored: a replaced bundle descriptor or a
    # manifest profile that disagrees with the committed descriptor is refused.
    good_desc = (root / "vitruvius.yaml").read_text()
    (root / "vitruvius.yaml").write_text(good_desc + "\n# tampered\n")
    if verify(root, man) == 0:
        problems.append("verify MUST refuse a bundle descriptor that differs from the committed one")
    (root / "vitruvius.yaml").write_text(good_desc)
    if verify_mutated(root, man, lambda x: x.update(profile="platform-baseline/v1")) == 0:
        problems.append("verify MUST refuse a manifest profile that disagrees with the committed descriptor")

    # canonical unit: normalize, and refuse absolute / traversal / outside-repo / empty.
    if canonical_unit("examples/./workload-onboarding/") != "examples/workload-onboarding":
        problems.append("canonical_unit must normalize a repo-relative path")
    for bad_unit in ("/etc/passwd", "../outside", "examples/../../etc", "", "C:/x"):
        try:
            canonical_unit(bad_unit)
            problems.append(f"canonical_unit must reject {bad_unit!r}")
        except PipelineError:
            pass
    if verify(root, man, unit="../escape") == 0:
        problems.append("verify MUST refuse a non-canonical / escaping deployable unit")

    # static Azure Pipelines contract test (YAML, not runtime).
    problems.extend(contract_test())

    # gate refuses (and writes no manifest) on a non-conformant plan.
    bad = stage("plan.regulated-noncompliant.json")
    bad_out = bad / "plan-manifest.json"
    if gate(bad, bad_out) == 0 or bad_out.exists():
        problems.append("gate MUST fail and write no manifest on a non-conformant plan")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd")

    g = sub.add_parser("gate")
    for a in ("--root", "--repository", "--commit", "--environment", "--unit", "--out"):
        g.add_argument(a, required=True)

    b = sub.add_parser("bundle")
    b.add_argument("--root", required=True)
    b.add_argument("--out", required=True)

    v = sub.add_parser("verify")
    for a in ("--root", "--manifest", "--repository", "--commit", "--environment", "--unit"):
        v.add_argument(a, required=True)

    r = sub.add_parser("receipt")
    r.add_argument("--manifest", required=True)
    r.add_argument("--approver", required=True)
    r.add_argument("--verify-result", required=True, dest="verify_result")
    r.add_argument("--apply-attempted", required=True, dest="apply_attempted")
    r.add_argument("--apply-result", required=True, dest="apply_result")
    r.add_argument("--apply-exit-code", required=True, dest="apply_exit_code")
    r.add_argument("--pipeline-result", required=True, dest="pipeline_result")
    r.add_argument("--completed-at", dest="completed_at", default=None)
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
        print("OK — verdict-input binding, fail-closed verify, exact-plan selection, bundle isolation, and per-outcome receipts all behave.")
        return 0

    dispatch = {"gate": cmd_gate, "bundle": cmd_bundle, "verify": cmd_verify, "receipt": cmd_receipt}
    if args.cmd not in dispatch:
        ap.error("need a subcommand (gate/bundle/verify/receipt) or --self-test")
    return dispatch[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
