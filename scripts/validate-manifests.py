#!/usr/bin/env python3
"""Validate every module manifest against the schema and the module's code.

This is the CI implementation of ADR 0011's validation contract:

  1. Schema validation — each modules/**/manifest.yaml parses as YAML and
     validates against schemas/module-manifest.schema.json.
  2. Coherence — the manifest agrees with the module's actual code:
       - metadata.name / metadata.area match the module's directory path
       - spec.inputs mirror variables.tf (names; required == no default)
       - spec.outputs mirror outputs.tf (names)
       - spec.dependencies.avm entries appear in main.tf (source + version)
       - spec.ships.policy / .monitoring entries resolve to a file in
         policy/ / monitoring/ or to a literal resource name in main.tf
       - spec.examples / spec.tests entries exist on disk
       - spec.cites.decisions / .anti_patterns resolve to real ADRs / APs
  3. Policy JSON — every modules/*/policy/*.json parses and carries the
     keys the modules' jsondecode() calls rely on.

Python (not PowerShell) because YAML parsing and JSON Schema validation need
real libraries: PyYAML and jsonschema. Both ship on GitHub-hosted runners or
install with `pip install pyyaml jsonschema`.

Exit code 0 when everything passes; 1 with one line per finding otherwise.
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

try:
    import jsonschema
except ImportError:
    sys.exit("jsonschema is required: pip install jsonschema")

REPO = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO / "schemas" / "module-manifest.schema.json"
ADR_DIR = REPO / "docs" / "decisions"
ANTI_PATTERNS = REPO / "docs" / "anti-patterns.md"

errors: list[str] = []


def err(path: Path, message: str) -> None:
    errors.append(f"{path.relative_to(REPO)}: {message}")


def hcl_blocks(text: str, kind: str) -> dict[str, str]:
    """Return {label: body} for every top-level `kind "label" {` block.

    A brace-counting scan, not a real HCL parser — sufficient for the
    top-level block structure this repo's Terraform uses. Brace characters
    inside string literals would confuse it; none of the scanned blocks
    contain any.
    """
    blocks: dict[str, str] = {}
    for match in re.finditer(rf'^{kind}\s+"([^"]+)"\s*\{{', text, re.MULTILINE):
        label = match.group(1)
        depth = 1
        pos = match.end()
        while pos < len(text) and depth > 0:
            if text[pos] == "{":
                depth += 1
            elif text[pos] == "}":
                depth -= 1
            pos += 1
        blocks[label] = text[match.end() : pos - 1]
    return blocks


def top_level_attrs(body: str) -> set[str]:
    """Attribute names assigned at depth 0 of a block body."""
    attrs: set[str] = set()
    depth = 0
    for line in body.splitlines():
        stripped = line.strip()
        if depth == 0:
            m = re.match(r"^([a-z_]+)\s*=", stripped)
            if m:
                attrs.add(m.group(1))
        depth += stripped.count("{") - stripped.count("}")
    return attrs


def validate_module(module_dir: Path, schema: dict) -> None:
    manifest_path = module_dir / "manifest.yaml"

    try:
        manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        err(manifest_path, f"invalid YAML: {str(exc).splitlines()[0]}")
        return

    try:
        jsonschema.validate(manifest, schema)
    except jsonschema.ValidationError as exc:
        err(manifest_path, f"schema violation at {'/'.join(map(str, exc.absolute_path))}: {exc.message}")
        return

    meta, spec = manifest["metadata"], manifest["spec"]

    # --- metadata matches the directory ---
    if meta["name"] != module_dir.name:
        err(manifest_path, f"metadata.name '{meta['name']}' != directory name '{module_dir.name}'")
    if meta["area"] != module_dir.parent.name:
        err(manifest_path, f"metadata.area '{meta['area']}' != area directory '{module_dir.parent.name}'")

    # --- inputs mirror variables.tf ---
    variables_tf = module_dir / "variables.tf"
    tf_vars = hcl_blocks(variables_tf.read_text(encoding="utf-8"), "variable") if variables_tf.exists() else {}
    declared = {i["name"]: i for i in spec["inputs"]}
    for name in sorted(set(tf_vars) - set(declared)):
        err(manifest_path, f"variables.tf declares '{name}' but spec.inputs does not")
    for name in sorted(set(declared) - set(tf_vars)):
        err(manifest_path, f"spec.inputs declares '{name}' but variables.tf does not")
    for name in sorted(set(declared) & set(tf_vars)):
        has_default = "default" in top_level_attrs(tf_vars[name])
        if declared[name]["required"] == has_default:
            expected = "false" if has_default else "true"
            err(manifest_path, f"input '{name}': required should be {expected} (variables.tf {'has' if has_default else 'has no'} default)")

    # --- outputs mirror outputs.tf ---
    outputs_tf = module_dir / "outputs.tf"
    tf_outputs = set(hcl_blocks(outputs_tf.read_text(encoding="utf-8"), "output")) if outputs_tf.exists() else set()
    manifest_outputs = {o["name"] for o in spec["outputs"]}
    for name in sorted(tf_outputs - manifest_outputs):
        err(manifest_path, f"outputs.tf declares '{name}' but spec.outputs does not")
    for name in sorted(manifest_outputs - tf_outputs):
        err(manifest_path, f"spec.outputs declares '{name}' but outputs.tf does not")

    # --- AVM dependencies appear in main.tf ---
    main_tf_path = module_dir / "main.tf"
    main_tf = main_tf_path.read_text(encoding="utf-8") if main_tf_path.exists() else ""
    for dep in spec["dependencies"]["avm"]:
        if dep["source"] not in main_tf:
            err(manifest_path, f"dependencies.avm source '{dep['source']}' not found in main.tf")
        elif not re.search(rf'version\s*=\s*"{re.escape(dep["version"])}"', main_tf):
            err(manifest_path, f"dependencies.avm '{dep['source']}' version '{dep['version']}' does not match main.tf")

    # --- ships entries resolve to a file or a resource name in main.tf ---
    # Substring match, not equality: resource names are commonly templated
    # ("${var.name_prefix}-tag-taxonomy"), so the manifest declares the stable
    # logical part of the name.
    resource_names = re.findall(r'name\s*=\s*"([^"]+)"', main_tf)
    for kind in ("policy", "monitoring"):
        for entry in spec["ships"][kind]:
            artifact = module_dir / kind / f"{entry}.json"
            if not artifact.exists() and not any(entry in name for name in resource_names):
                err(manifest_path, f"ships.{kind} '{entry}': no {kind}/{entry}.json and no resource name containing '{entry}' in main.tf")

    # --- declared examples and tests exist; no undeclared ones ---
    declared_examples = {e["name"] for e in spec["examples"]}
    actual_examples = {p.name for p in (module_dir / "examples").iterdir() if p.is_dir()} if (module_dir / "examples").is_dir() else set()
    for name in sorted(declared_examples - actual_examples):
        err(manifest_path, f"spec.examples declares '{name}' but examples/{name}/ does not exist")
    for name in sorted(actual_examples - declared_examples):
        err(manifest_path, f"examples/{name}/ exists but spec.examples does not declare it")

    declared_tests = {t["name"] for t in spec["tests"]}
    actual_tests = {p.stem.removesuffix(".tftest") for p in (module_dir / "tests").glob("*.tftest.hcl")} if (module_dir / "tests").is_dir() else set()
    for name in sorted(declared_tests - actual_tests):
        err(manifest_path, f"spec.tests declares '{name}' but tests/{name}.tftest.hcl does not exist")
    for name in sorted(actual_tests - declared_tests):
        err(manifest_path, f"tests/{name}.tftest.hcl exists but spec.tests does not declare it")

    # --- citations resolve ---
    for adr in spec["cites"]["decisions"]:
        adr_id = adr.removeprefix("ADR-")
        if not list(ADR_DIR.glob(f"{adr_id}-*.md")):
            err(manifest_path, f"cites.decisions '{adr}': no docs/decisions/{adr_id}-*.md")
    ap_text = ANTI_PATTERNS.read_text(encoding="utf-8")
    for ap in spec["cites"]["anti_patterns"]:
        if not re.search(rf"^## {ap}\b", ap_text, re.MULTILINE):
            err(manifest_path, f"cites.anti_patterns '{ap}': no '## {ap}' heading in docs/anti-patterns.md")


def validate_policy_json(module_dir: Path) -> None:
    for policy_path in sorted((module_dir / "policy").glob("*.json")) if (module_dir / "policy").is_dir() else []:
        try:
            policy = json.loads(policy_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            err(policy_path, f"invalid JSON: {exc}")
            continue
        for key in ("displayName", "description", "mode", "policyRule"):
            if key not in policy:
                err(policy_path, f"missing required key '{key}'")


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    module_dirs = sorted(p.parent for p in REPO.glob("modules/*/*/manifest.yaml"))
    if not module_dirs:
        print("No manifests found under modules/*/*/", file=sys.stderr)
        return 1

    for module_dir in module_dirs:
        validate_module(module_dir, schema)
        validate_policy_json(module_dir)

    if errors:
        for line in errors:
            print(f"FAIL {line}", file=sys.stderr)
        print(f"\n{len(errors)} finding(s) across {len(module_dirs)} modules.", file=sys.stderr)
        return 1

    print(f"OK — {len(module_dirs)} manifests schema-valid and coherent with code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
