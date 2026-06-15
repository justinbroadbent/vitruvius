#!/usr/bin/env python3
"""Evaluate a deployment's rendered Terraform plan against its conformance profile.

The plan-time half of ADR 0025: a deployable root declares a descriptor
(`vitruvius.yaml`) naming a conformance profile; this script checks the
profile's rules against the resources in a `terraform show -json` plan, and
fails on any unwaived violation.

The profile checks two distinct things ADR 0025 cares about:

  * completeness — required capabilities are present (`require_resource`), and
    forbidden ones are absent (`forbid_resource`). This is the "someone left a
    brick out" half the ADR exists for.
  * correctness — present resources carry safe properties (`assert_property`),
    which **fail closed**: a missing or unknown value on a targeted resource is
    a violation unless the rule opts into `on_missing: skip`.

Exemptions are not just strings. A descriptor exception waives a rule only when
it references a registry record (`policies/conformance-exemptions.yaml`) that
exists, is owned, is unexpired, covers that exact rule, and corresponds to a
rule the plan actually failed (ADR 0025 §4 / ADR 0008).

Known limit: completeness is checked against one root's plan, so a capability a
workload *consumes* from another root (a platform-provided identity, say) is out
of view. `require_resource` rules therefore name only what a root must create
itself; the cross-root provides/requires graph is deferred (ADR 0025).

Usage:
  evaluate-conformance.py <descriptor.yaml> <plan.json>   # gate one root
  evaluate-conformance.py --self-test                     # descriptors + fixtures (CI)

Exit 0 when the plan conforms; 1 with one line per violation otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date, timedelta
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
REGISTRY_PATH = REPO / "policies" / "conformance-exemptions.yaml"
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


def load_registry(path: Path = REGISTRY_PATH) -> dict:
    if not path.exists():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return data.get("exemptions", {}) or {}


def iter_resources(plan: dict):
    def walk(module: dict):
        for r in module.get("resources", []):
            yield r
        for child in module.get("child_modules", []):
            yield from walk(child)

    yield from walk(plan.get("planned_values", {}).get("root_module", {}))


def _matching(resources: list, types: list, include_data: bool = False) -> list:
    out = []
    for r in resources:
        # Data sources are not resources this root configures — they must not
        # satisfy require_resource, trigger forbid_resource, or be asserted on.
        # mode == "managed" is the default proof boundary (absent mode = managed).
        if not include_data and r.get("mode", "managed") != "managed":
            continue
        if "*" in types or r["type"] in types:
            out.append(r)
    return out


def _assert_one(rule: dict, res: dict) -> str | None:
    field = rule["field"]
    values = res.get("values", {})
    present = field in values and values[field] is not None
    if not present:
        # Fail closed by default: a targeted resource with a missing/unknown
        # security property is a violation unless the rule opts out.
        return None if rule.get("on_missing", "fail") == "skip" else f"{field} is missing or unknown (fails closed)"
    v = values[field]
    if "equals" in rule:
        return None if v == rule["equals"] else f"{field}={v!r}, want {rule['equals']!r}"
    if "not_equals" in rule:
        return None if v != rule["not_equals"] else f"{field} must not be {rule['not_equals']!r}"
    if "in" in rule:
        return None if v in rule["in"] else f"{field}={v!r} not in {rule['in']}"
    if "exists" in rule:
        return None if present == rule["exists"] else f"{field} existence != {rule['exists']}"
    raise ConformanceError(f"assert_property rule '{rule['id']}' has no operator")


def _parse_date(value) -> date:
    return value if isinstance(value, date) else date.fromisoformat(str(value))


def apply_exemptions(exceptions: list, registry: dict, failed_rules: set, today: date | None = None):
    """Return (waived_rule_ids, findings). An exemption waives only when valid."""
    today = today or date.today()
    waived: set[str] = set()
    findings: list[str] = []
    for ex in exceptions:
        rule, exid = ex["rule"], ex["exemption"]
        rec = registry.get(exid)
        if rec is None:
            findings.append(f"exemption '{exid}' (for rule {rule}) is not in the exemption registry")
            continue
        if rec.get("rule") != rule:
            findings.append(f"exemption '{exid}' covers rule '{rec.get('rule')}', not '{rule}'")
            continue
        if not rec.get("owner"):
            findings.append(f"exemption '{exid}' has no owner")
            continue
        expires = rec.get("expires")
        if expires is None or _parse_date(expires) < today:
            findings.append(f"exemption '{exid}' is missing or past its expiry ({expires})")
            continue
        if rule not in failed_rules:
            findings.append(f"exemption '{exid}' waives rule '{rule}', which did not fail — remove it")
            continue
        waived.add(rule)
    return waived, findings


def evaluate(descriptor: dict, plan: dict, profiles_dir: Path = PROFILES_DIR, registry: dict | None = None):
    """Return (failures, exemption_findings). Either being non-empty means the gate fails."""
    spec = descriptor["spec"]
    profile = load_profile(spec["profile"], profiles_dir)
    resources = list(iter_resources(plan))
    failures: list[dict] = []

    for rule in profile["spec"]["rules"]:
        kind = rule.get("kind", "assert_property")
        rid, cites = rule["id"], rule.get("cites", [])
        types = rule.get("resource_types", ["*"])
        if kind == "assert_property":
            for res in _matching(resources, types):
                detail = _assert_one(rule, res)
                if detail:
                    failures.append({"rule": rid, "resource": res["address"], "detail": detail, "cites": cites})
        elif kind == "require_resource":
            minimum = rule.get("minimum", 1)
            found = len(_matching(resources, types))
            if found < minimum:
                failures.append({"rule": rid, "resource": "(plan)",
                                 "detail": f"requires ≥{minimum} managed of {types}; found {found}", "cites": cites})
        elif kind == "forbid_resource":
            for res in _matching(resources, types):
                failures.append({"rule": rid, "resource": res["address"],
                                 "detail": f"resource type {res['type']} is forbidden", "cites": cites})
        elif kind == "tags_match_descriptor":
            # §5: the descriptor declares the workload's classification; the plan must
            # not contradict it. The resource group (the tag source) must carry the exact
            # values; any managed resource that *explicitly* carries a controlled tag must
            # agree; types the profile names as direct-tag-required must carry them. A
            # resource with no controlled tag is fine — Azure Policy inherits it from the
            # RG (we do not guess universal taggability or duplicate the runtime layer).
            expected = {"data-classification": spec.get("data-classification"),
                        "business-criticality": spec.get("business-criticality")}
            rg_types = rule.get("resource_group_types", ["azurerm_resource_group"])
            direct_types = rule.get("direct_tag_required", [])
            for res in _matching(resources, ["*"]):
                tags = res.get("values", {}).get("tags") or {}
                must_carry = res["type"] in rg_types or res["type"] in direct_types
                for tagkey, want in expected.items():
                    have = tags.get(tagkey)
                    if have is None:
                        if must_carry:
                            failures.append({"rule": rid, "resource": res["address"],
                                             "detail": f"{tagkey} tag missing; this type must carry it directly (want {want!r})", "cites": cites})
                    elif have != want:
                        failures.append({"rule": rid, "resource": res["address"],
                                         "detail": f"{tagkey}={have!r} contradicts the descriptor ({want!r})", "cites": cites})
        else:
            raise ConformanceError(f"unknown rule kind '{kind}' in rule '{rid}'")

    failed_rules = {f["rule"] for f in failures}
    waived, exemption_findings = apply_exemptions(spec.get("exceptions", []) or [], registry or {}, failed_rules)
    kept = [f for f in failures if f["rule"] not in waived]
    return kept, exemption_findings


def validate_descriptor(path: Path, schema: dict) -> dict:
    desc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    jsonschema.validate(desc, schema)
    return desc


def _descriptor(profile: str, exceptions: list | None = None) -> dict:
    # Includes the now-required classification fields so test descriptors are valid.
    return {"apiVersion": "vitruvius.io/v1", "kind": "TerraformRoot",
            "metadata": {"name": "self-test", "owner": "self-test"},
            "spec": {"scope": "workload_resource_group", "profile": profile,
                     "business-criticality": "tier-1", "data-classification": "confidential",
                     "exceptions": exceptions or []}}


def self_test() -> list[str]:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    problems: list[str] = []

    # 1. Every example descriptor validates and names a real profile.
    for d in EXAMPLE_DESCRIPTORS:
        try:
            desc = validate_descriptor(d, schema)
            load_profile(desc["spec"]["profile"])
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{d.relative_to(REPO)}: {exc}")

    fx = lambda n: json.loads((FIXTURES / n).read_text(encoding="utf-8"))  # noqa: E731
    compliant, noncompliant, nullprop = fx("plan.regulated-compliant.json"), fx("plan.regulated-noncompliant.json"), fx("plan.regulated-null-property.json")
    reg = _descriptor("regulated-workload/v1")

    # 2. A compliant plan passes.
    kept, find = evaluate(reg, compliant, registry={})
    if kept or find:
        problems.append(f"compliant fixture should pass; failed on {[k['rule'] for k in kept]} findings={find}")

    # 3. A non-compliant plan fails on every rule kind (assert, require, forbid).
    kept, _ = evaluate(reg, noncompliant, registry={})
    expected = {"keyvault.no-public-access", "storage.no-public-blob", "location.approved-regions",
                "identity.workload-federation-required", "identity.no-static-secret", "tags.match-descriptor"}
    got = {k["rule"] for k in kept}
    if got != expected:
        problems.append(f"non-compliant fixture failures {sorted(got)} != expected {sorted(expected)}")

    # 4. A missing/unknown security property fails closed.
    kept, _ = evaluate(reg, nullprop, registry={})
    if {k["rule"] for k in kept} != {"keyvault.no-public-access"}:
        problems.append(f"null-property fixture should fail closed on keyvault.no-public-access; got {[k['rule'] for k in kept]}")

    # 5. Exemption lifecycle: a valid exemption waives; fake / expired / wrong-rule do not.
    # timedelta, not .replace(year=...), so the test is safe on Feb 29.
    future, past = (date.today() + timedelta(days=365)).isoformat(), (date.today() - timedelta(days=365)).isoformat()
    registry = {
        "EX-VALID": {"rule": "keyvault.no-public-access", "owner": "payments-team", "expires": future, "justification": "test"},
        "EX-EXPIRED": {"rule": "keyvault.no-public-access", "owner": "payments-team", "expires": past, "justification": "test"},
        "EX-WRONGRULE": {"rule": "storage.no-public-blob", "owner": "payments-team", "expires": future, "justification": "test"},
    }
    kept, find = evaluate(_descriptor("regulated-workload/v1", [{"rule": "keyvault.no-public-access", "exemption": "EX-VALID"}]), noncompliant, registry=registry)
    if "keyvault.no-public-access" in {k["rule"] for k in kept} or find:
        problems.append("valid exemption should waive keyvault.no-public-access without findings")
    for exid, why in [("EX-NOPE", "missing"), ("EX-EXPIRED", "expired"), ("EX-WRONGRULE", "wrong-rule")]:
        kept, find = evaluate(_descriptor("regulated-workload/v1", [{"rule": "keyvault.no-public-access", "exemption": exid}]), noncompliant, registry=registry)
        if "keyvault.no-public-access" not in {k["rule"] for k in kept} or not find:
            problems.append(f"{why} exemption ({exid}) must NOT waive and must raise a finding")

    # 6. Data sources are ignored — a data-source of a required type does not satisfy require_resource.
    kept, _ = evaluate(reg, fx("plan.data-source-ignored.json"), registry={})
    if "identity.workload-federation-required" not in {k["rule"] for k in kept}:
        problems.append("a data-source federated identity must NOT satisfy require_resource (managed-only proof boundary)")

    # 7. §5 tag matching: classification/criticality contradictions fail; non-taggable resources skip.
    def _plan(*rs):
        return {"planned_values": {"root_module": {"resources": list(rs), "child_modules": []}}}

    def _r(t, a, **v):
        return {"type": t, "address": a, "mode": "managed", "values": v}

    fic = _r("azurerm_federated_identity_credential", "fic")
    for label, tags in [("data-classification", {"data-classification": "restricted", "business-criticality": "tier-1"}),
                        ("business-criticality", {"data-classification": "confidential", "business-criticality": "tier-0"})]:
        plan = _plan(fic, _r("azurerm_resource_group", "rg", location="eastus", tags=tags))
        if "tags.match-descriptor" not in {k["rule"] for k in evaluate(reg, plan, registry={})[0]}:
            problems.append(f"a resource-group {label} contradicting the descriptor must fail tags.match-descriptor")

    ok_rg = _r("azurerm_resource_group", "rg", location="eastus", tags={"data-classification": "confidential", "business-criticality": "tier-1"})
    skipped = _plan(fic, ok_rg, _r("azurerm_role_assignment", "ra"))
    if {k["rule"] for k in evaluate(reg, skipped, registry={})[0]}:
        problems.append("a non-taggable resource with no controlled tags must be skipped, not failed")

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
        print("OK — descriptors valid; completeness + correctness + forbid rules and exemption lifecycle all behave.")
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
    failures, exemption_findings = evaluate(desc, plan, registry=load_registry())
    for f in failures:
        cites = f" [{', '.join(f['cites'])}]" if f["cites"] else ""
        print(f"FAIL {f['rule']} — {f['resource']}: {f['detail']}{cites}", file=sys.stderr)
    for finding in exemption_findings:
        print(f"FAIL exemption — {finding}", file=sys.stderr)
    total = len(failures) + len(exemption_findings)
    if total:
        print(f"\n{total} conformance failure(s) against profile {desc['spec']['profile']}.", file=sys.stderr)
        return 1
    print(f"OK — plan conforms to profile {desc['spec']['profile']}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
