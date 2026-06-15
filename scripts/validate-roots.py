#!/usr/bin/env python3
"""Discover every deployable Terraform root and statically check it is conformance-ready.

A *deployable root* is a directory `examples/<name>/` with a `main.tf` meant to be
applied — the platform landing zone, a workload-onboarding root. Module examples
(`modules/*/*/examples/*`) are test harnesses, not deployable roots, and are out of
scope here.

For each root this asserts — with no Terraform, Azure, or network — that:
  * it declares a conformance descriptor (`vitruvius.yaml`) — ADR 0025;
  * the descriptor is schema-valid and its profile resolves to a real profile file;
  * a provider lockfile (`.terraform.lock.hcl`) is committed — ADR 0020 applies with
    `-lockfile=readonly`, which requires the committed lock;
  * no Terraform state is committed — the repo ships no state (ADR 0017);
  * no state-backend secret is hard-coded in the root's `.tf` files.

This is the root-set companion to `evaluate-conformance.py` (which proves ONE rendered
plan): it proves the *inventory* of roots is each well-formed, catching "someone added a
root and forgot the descriptor / lockfile" before any plan or apply runs.

Exit 0 if every root is ready; 1 with one line per finding otherwise.
`--self-test` exercises the checks against good and deliberately-broken fixtures (CI).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")
try:
    import jsonschema
except ImportError:
    sys.exit("jsonschema is required: pip install jsonschema")

REPO = Path(__file__).resolve().parent.parent
EVALUATOR_PATH = REPO / "scripts" / "evaluate-conformance.py"

# Reuse the conformance evaluator's descriptor/profile logic rather than re-implement it.
_spec = importlib.util.spec_from_file_location("evaluate_conformance", EVALUATOR_PATH)
ev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ev)

# A literal secret on a backend attribute. Pure interpolations ("${var.x}") carry a '$'
# and are intentionally NOT matched — only hard-coded literals are.
SECRET_RE = re.compile(
    r'(?i)\b(access_key|secret_access_key|sas_token|account_key|client_secret)\s*=\s*"[^"$]+"'
)


def discover_roots(base: Path = REPO) -> list[Path]:
    """Deployable roots are examples/<name>/ directories carrying a main.tf."""
    return sorted(p.parent for p in base.glob("examples/*/main.tf"))


def check_root(root: Path, schema: dict) -> list[str]:
    findings: list[str] = []

    desc_path = root / "vitruvius.yaml"
    if not desc_path.exists():
        findings.append("no conformance descriptor (vitruvius.yaml) — every deployable root must declare one (ADR 0025)")
    else:
        desc = None
        try:
            desc = ev.validate_descriptor(desc_path, schema)
        except jsonschema.ValidationError as exc:
            findings.append(f"descriptor fails the schema: {exc.message}")
        except Exception as exc:  # noqa: BLE001 — malformed YAML, unreadable file
            findings.append(f"descriptor unreadable: {exc}")
        if desc is not None:
            profile_ref = desc.get("spec", {}).get("profile")
            try:
                ev.load_profile(profile_ref)
            except ev.ConformanceError as exc:
                findings.append(f"profile does not resolve: {exc}")

    if not (root / ".terraform.lock.hcl").exists():
        findings.append("no committed provider lockfile (.terraform.lock.hcl) — ADR 0020 applies with -lockfile=readonly")

    state = sorted(p.name for p in root.glob("*.tfstate*"))
    if state:
        findings.append(f"Terraform state is committed ({', '.join(state)}) — the repo ships no state (ADR 0017)")

    for tf in sorted(root.glob("*.tf")):
        if SECRET_RE.search(tf.read_text(encoding="utf-8")):
            findings.append(f"{tf.name} hard-codes a state-backend secret — secrets must never be committed")

    return findings


def validate(base: Path = REPO) -> list[str]:
    schema = json.loads(ev.SCHEMA_PATH.read_text(encoding="utf-8"))
    roots = discover_roots(base)
    if not roots:
        return ["no deployable roots found under examples/*/ — expected at least the reference landing zone"]
    problems: list[str] = []
    for root in roots:
        for f in check_root(root, schema):
            problems.append(f"{root.relative_to(base).as_posix()}: {f}")
    return problems


def self_test() -> list[str]:
    problems: list[str] = []
    schema = json.loads(ev.SCHEMA_PATH.read_text(encoding="utf-8"))

    def descriptor(**overrides) -> str:
        spec = {"scope": "workload_resource_group", "profile": "regulated-workload/v1",
                "business-criticality": "tier-1", "data-classification": "confidential"}
        spec.update(overrides.pop("spec", {}))
        for k in list(overrides):
            if overrides[k] is None:
                spec.pop(k, None)
        return yaml.safe_dump({"apiVersion": "vitruvius.io/v1", "kind": "TerraformRoot",
                               "metadata": {"name": "self-test", "owner": "self-test"}, "spec": spec})

    def root_with(desc: str | None, lock: bool = True, state: bool = False, tf_extra: str = "") -> Path:
        d = Path(tempfile.mkdtemp())
        (d / "main.tf").write_text('module "naming" {\n  source = "../../modules/foundation/naming"\n}\n' + tf_extra)
        if desc is not None:
            (d / "vitruvius.yaml").write_text(desc)
        if lock:
            (d / ".terraform.lock.hcl").write_text("# provider lock\n")
        if state:
            (d / "terraform.tfstate").write_text("{}")
        return d

    def expect(label: str, root: Path, needle: str | None):
        findings = check_root(root, schema)
        if needle is None and findings:
            problems.append(f"{label}: a well-formed root must pass, got {findings}")
        elif needle is not None and not any(needle in f for f in findings):
            problems.append(f"{label}: expected a finding containing {needle!r}, got {findings}")

    expect("good root", root_with(descriptor()), None)
    expect("missing descriptor", root_with(None), "no conformance descriptor")
    expect("unresolvable profile", root_with(descriptor(spec={"profile": "nonexistent/v9"})), "profile does not resolve")
    expect("schema-invalid descriptor", root_with(descriptor(**{"data-classification": None})), "fails the schema")
    expect("missing lockfile", root_with(descriptor(), lock=False), "no committed provider lockfile")
    expect("committed state", root_with(descriptor(), state=True), "state is committed")
    secret_tf = '\nterraform {\n  backend "azurerm" {\n    access_key = "deadbeefsecret"\n  }\n}\n'
    expect("hard-coded backend secret", root_with(descriptor(), tf_extra=secret_tf), "state-backend secret")
    # an interpolated value must NOT be flagged as a secret.
    interp_tf = '\nlocals {\n  access_key = "${var.key}"\n}\n'
    if any("secret" in f for f in check_root(root_with(descriptor(), tf_extra=interp_tf), schema)):
        problems.append("an interpolated value must not be flagged as a hard-coded secret")

    # discovery must find the repo's real deployable roots, and they must all pass.
    if len(discover_roots()) < 2:
        problems.append("discovery must find the repo's deployable roots (landing zone + workload onboarding)")
    if validate():
        problems.append("the repo's own deployable roots must already be conformance-ready")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        problems = self_test()
        if problems:
            for p in problems:
                print(f"FAIL {p}", file=sys.stderr)
            print(f"\n{len(problems)} finding(s).", file=sys.stderr)
            return 1
        print("OK — root discovery and the descriptor/profile/lockfile/state/secret checks all behave.")
        return 0

    problems = validate()
    if problems:
        for p in problems:
            print(f"FAIL {p}", file=sys.stderr)
        print(f"\n{len(problems)} finding(s) across deployable roots.", file=sys.stderr)
        return 1
    roots = discover_roots()
    names = ", ".join(r.relative_to(REPO).as_posix() for r in roots)
    print(f"OK — {len(roots)} deployable root(s) conformance-ready: {names}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
