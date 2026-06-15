#!/usr/bin/env python3
"""Drift-check every vocabulary representation against the single authored source.

modules/foundation/tags/vocabularies.yaml is the source of the controlled-tag
vocabularies (ADR 0010). This confirms the authored copies still agree:

  - the tags module's variable validations (variables.tf)
  - the allowed-values-*.json Azure Policy definitions
  - the conformance descriptor schema enums (ADR 0025 §5)

`local.vocabularies` derives from the YAML directly (`yamldecode`), and main.tf's
`terraform_data` invariant checks the policy JSON against it at plan time. This
script covers the representations that are hand-authored copies, so a vocabulary
cannot be changed in one place and forgotten in another.

Exit 0 when everything agrees; 1 with one line per drift otherwise.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "modules" / "foundation" / "tags" / "vocabularies.yaml"
VARS = REPO / "modules" / "foundation" / "tags" / "variables.tf"
POLICY_DIR = REPO / "modules" / "foundation" / "tags" / "policy"
SCHEMA = REPO / "schemas" / "conformance-descriptor.schema.json"

errors: list[str] = []


def check(name: str, expected: list, actual: list, where: str) -> None:
    if sorted(expected) != sorted(actual):
        errors.append(f"{where}: '{name}' = {actual}; vocabularies.yaml has {expected}")


def hcl_contains(text: str, var: str) -> list | None:
    m = re.search(r"contains\(\[([^\]]*)\],\s*var\." + re.escape(var) + r"\b", text)
    return None if not m else re.findall(r'"([^"]+)"', m.group(1))


def main() -> int:
    vocab = yaml.safe_load(SRC.read_text(encoding="utf-8"))
    vars_tf = VARS.read_text(encoding="utf-8")
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))

    for key, var in [("data_classification", "data_classification"), ("business_criticality", "business_criticality"),
                     ("env", "env"), ("lifecycle", "lifecycle_stage")]:
        got = hcl_contains(vars_tf, var)
        if got is None:
            errors.append(f"variables.tf: no contains(...) validation found for var.{var}")
        else:
            check(key, vocab[key], got, f"variables.tf var.{var}")

    for key, fname in [("data_classification", "allowed-values-data-classification.json"),
                       ("business_criticality", "allowed-values-business-criticality.json"),
                       ("env", "allowed-values-env.json")]:
        pol = json.loads((POLICY_DIR / fname).read_text(encoding="utf-8"))
        check(key, vocab[key], pol["policyRule"]["if"]["allOf"][1]["notIn"], f"policy/{fname}")

    spec_props = schema["properties"]["spec"]["properties"]
    check("data_classification", vocab["data_classification"], spec_props["data-classification"]["enum"],
          "conformance-descriptor.schema.json data-classification")
    check("business_criticality", vocab["business_criticality"], spec_props["business-criticality"]["enum"],
          "conformance-descriptor.schema.json business-criticality")

    if errors:
        for e in errors:
            print(f"FAIL {e}", file=sys.stderr)
        print(f"\n{len(errors)} vocabulary drift finding(s).", file=sys.stderr)
        return 1
    print(f"OK — {len(vocab)} vocabularies single-sourced; variable validations, policies, and the descriptor schema agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
