#!/usr/bin/env python3
"""Evaluate a deployment's rendered Terraform plan against its conformance profile.

This is the plan-time half of ADR 0025: a deployable root declares a descriptor
(`vitruvius.yaml`) naming a conformance profile; this script checks the profile's
rules against the resources in a `terraform show -json` plan, and fails the build
on any unwaived violation.

The rules assert **real planned properties** (`public_network_access_enabled`,
`https_only`, `location`), not which modules a root happens to call — a module
cannot satisfy a rule by name alone.

Usage:
  evaluate-conformance.py <descriptor.yaml> <plan.json>   # gate one root
  evaluate-conformance.py --self-test                     # validate descriptors + fixtures (CI)

Not wired to a live plan here: CI runs the self-test against committed fixtures,
because producing a real azurerm plan needs Azure credentials. Feeding a real
`terraform show -json` into this gate on every PR is the deployment pipeline's
job (ADR 0020), itself a planned control — see docs/IMPLEMENTATION-STATUS.md.

Exit 0 when the plan conforms; 1 with one line per violation otherwise.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
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
PROFILES_DIR = REPO / "profiles"
SCHEMA_PATH = REPO / "schemas" / "conformance-descriptor.schema.json"
FIXTURES = REPO / "scripts" / "conformance" / "fixtures"
EXAMPLE_DESCRIPTORS = sorted(REPO.glob("examples/*/vitruvius.yaml"))


class ConformanceError(Exception):
    pass


def load_profile(profile_ref: str, profiles_dir: Path = PROFILES_DIR) -> dict:
    m = re.fullmatch(r"([a-z0-9-]+)/v([0-9]+)", profile_ref)
    if not m:
        raise ConformanceError(f"malformed profile reference '{profile_ref}' (want name/vN)")
    name, version = m.group(1), "v" + m.group(2)
    path = profiles_dir / f"{name}.yaml"
    if not path.exists():
        raise ConformanceError(f"no profile file profiles/{name}.yaml for '{profile_ref}'")
    prof = yaml.safe_load(path.read_text(encoding="utf-8"))
    have = prof.get("metadata", {}).get("version")
    if have != version:
        raise ConformanceError(f"profile {name} is {have}; descriptor asked for {version}")
    return prof


def iter_resources(plan: dict):
    def walk(module: dict):
        for r in module.get("resources", []):
            yield r
        for child in module.get("child_modules", []):
            yield from walk(child)

    yield from walk(plan.get("planned_values", {}).get("root_module", {}))


def _check(assertion: dict, values: dict) -> tuple[bool, bool]:
    """Return (applicable, ok). A resource missing the asserted field is not applicable."""
    field = assertion["field"]
    if values.get(field) is None:
        return False, True
    v = values[field]
    if "equals" in assertion:
        return True, v == assertion["equals"]
    if "not_equals" in assertion:
        return True, v != assertion["not_equals"]
    if "in" in assertion:
        return True, v in assertion["in"]
    if "exists" in assertion:
        return True, (v is not None) == assertion["exists"]
    raise ConformanceError(f"rule assertion has no known operator: {assertion}")


def evaluate(descriptor: dict, plan: dict, profiles_dir: Path = PROFILES_DIR) -> list[dict]:
    spec = descriptor["spec"]
    profile = load_profile(spec["profile"], profiles_dir)
    waived = {e["rule"] for e in spec.get("exceptions", []) or []}
    resources = list(iter_resources(plan))
    failures: list[dict] = []
    for rule in profile["spec"]["rules"]:
        if rule["id"] in waived:
            continue
        types = rule["resource_types"]
        for res in resources:
            if "*" not in types and res["type"] not in types:
                continue
            applicable, ok = _check(rule["assert"], res.get("values", {}))
            if applicable and not ok:
                failures.append({
                    "rule": rule["id"],
                    "resource": res["address"],
                    "detail": rule["description"],
                    "cites": rule.get("cites", []),
                })
    return failures


def validate_descriptor(path: Path, schema: dict) -> dict:
    desc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    jsonschema.validate(desc, schema)
    return desc


def self_test() -> list[str]:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    problems: list[str] = []

    # 1. Every example descriptor validates against the schema and names a real profile.
    for d in EXAMPLE_DESCRIPTORS:
        try:
            desc = validate_descriptor(d, schema)
            load_profile(desc["spec"]["profile"])
        except Exception as exc:  # noqa: BLE001 — surface any failure as a finding
            problems.append(f"{d.relative_to(REPO)}: {exc}")

    # 2. The evaluator passes a compliant plan, fails a non-compliant one, and honors exemptions.
    reg = {
        "apiVersion": "vitruvius.io/v1", "kind": "TerraformRoot",
        "metadata": {"name": "self-test", "owner": "self-test"},
        "spec": {"scope": "workload_resource_group", "profile": "regulated-workload/v1", "exceptions": []},
    }
    compliant = json.loads((FIXTURES / "plan.regulated-compliant.json").read_text(encoding="utf-8"))
    noncompliant = json.loads((FIXTURES / "plan.regulated-noncompliant.json").read_text(encoding="utf-8"))

    f_ok = evaluate(reg, compliant)
    if f_ok:
        problems.append(f"compliant fixture should pass; failed on {[x['rule'] for x in f_ok]}")

    f_bad = evaluate(reg, noncompliant)
    expected = {"keyvault.no-public-access", "storage.no-public-blob", "location.approved-regions"}
    got = {x["rule"] for x in f_bad}
    if got != expected:
        problems.append(f"non-compliant fixture failures {sorted(got)} != expected {sorted(expected)}")

    waived = copy.deepcopy(reg)
    waived["spec"]["exceptions"] = [{"rule": r, "exemption": "EX-0001"} for r in expected]
    f_waived = evaluate(waived, noncompliant)
    if f_waived:
        problems.append(f"exemptions should waive every failure; still failing {[x['rule'] for x in f_waived]}")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description="Evaluate a Terraform plan against its conformance profile (ADR 0025).")
    ap.add_argument("descriptor", nargs="?", help="path to the root's vitruvius.yaml descriptor")
    ap.add_argument("plan", nargs="?", help="path to a terraform show -json plan")
    ap.add_argument("--self-test", action="store_true", help="validate example descriptors and run fixtures (CI)")
    args = ap.parse_args()

    if args.self_test:
        problems = self_test()
        if problems:
            for p in problems:
                print(f"FAIL {p}", file=sys.stderr)
            print(f"\n{len(problems)} finding(s).", file=sys.stderr)
            return 1
        print("OK — descriptors valid; evaluator passes compliant, fails non-compliant, honors exemptions.")
        return 0

    if not (args.descriptor and args.plan):
        ap.error("need <descriptor> <plan>, or --self-test")

    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        desc = validate_descriptor(Path(args.descriptor), schema)
    except jsonschema.ValidationError as exc:
        print(f"FAIL descriptor invalid: {exc.message}", file=sys.stderr)
        return 1
    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    failures = evaluate(desc, plan)
    if failures:
        for f in failures:
            cites = f" [{', '.join(f['cites'])}]" if f["cites"] else ""
            print(f"FAIL {f['rule']} — {f['resource']}: {f['detail']}{cites}", file=sys.stderr)
        print(f"\n{len(failures)} conformance failure(s) against profile {desc['spec']['profile']}.", file=sys.stderr)
        return 1
    print(f"OK — plan conforms to profile {desc['spec']['profile']}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
