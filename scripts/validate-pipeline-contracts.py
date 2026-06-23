#!/usr/bin/env python3
"""Validate OpenGenome pipeline contracts without external dependencies."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PIPELINES = ROOT / "core" / "tabs" / "open-genome" / "pipelines"
WORKFLOWS = {
    "open-genome": {"fastq", "long_reads", "alignment"},
    "vcf-annotate": {"vcf"},
    "denovo-assembly": {"long_reads"},
}
REQUIRED_FILES = (
    "main.nf",
    "nextflow.config",
    "nextflow_schema.json",
    "modules.json",
    "nf-test.config",
    "conf/base.config",
    "conf/modules.config",
    "conf/test.config",
    "assets/samplesheet_schema.json",
    "assets/test_samplesheet.csv",
    "docs/usage.md",
    "docs/output.md",
    "tests/default.nf.test",
    "tests/nextflow.config",
)


def fail(message: str) -> None:
    print(f"pipeline contract error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)} is invalid JSON: {exc}")


def require_files() -> None:
    for workflow in WORKFLOWS:
        root = PIPELINES / workflow
        for rel in REQUIRED_FILES:
            path = root / rel
            if not path.is_file():
                fail(f"missing {path.relative_to(ROOT)}")


def validate_schema_files() -> None:
    for workflow in WORKFLOWS:
        root = PIPELINES / workflow
        params_schema = load_json(root / "nextflow_schema.json")
        sample_schema = load_json(root / "assets" / "samplesheet_schema.json")
        if params_schema.get("title", "").strip() == "":
            fail(f"{workflow}/nextflow_schema.json has no title")
        props = sample_schema.get("properties", {})
        input_type = props.get("input_type", {})
        allowed = set()
        if "const" in input_type:
            allowed.add(str(input_type["const"]))
        allowed.update(str(value) for value in input_type.get("enum", []))
        expected = WORKFLOWS[workflow]
        if allowed != expected:
            fail(f"{workflow} samplesheet_schema input_type {sorted(allowed)} != expected {sorted(expected)}")


def validate_test_samplesheets() -> None:
    for workflow, allowed in WORKFLOWS.items():
        path = PIPELINES / workflow / "assets" / "test_samplesheet.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        if not rows:
            fail(f"{path.relative_to(ROOT)} has no rows")
        for row in rows:
            input_type = (row.get("input_type") or "").strip()
            if input_type not in allowed:
                fail(f"{workflow} test samplesheet uses {input_type}, expected one of {sorted(allowed)}")


def validate_presets() -> None:
    presets_dir = PIPELINES / "presets"
    for path in sorted(presets_dir.glob("*.yml")):
        text = path.read_text(encoding="utf-8")
        workflow = None
        preset = None
        for line in text.splitlines():
            if line.startswith("workflow:"):
                workflow = line.split(":", 1)[1].strip()
            elif line.startswith("preset:"):
                preset = line.split(":", 1)[1].strip()
        if not preset:
            fail(f"{path.relative_to(ROOT)} has no preset key")
        if workflow not in WORKFLOWS:
            fail(f"{path.relative_to(ROOT)} references unknown workflow {workflow!r}")


def validate_contract_doc() -> None:
    text = (PIPELINES / "pipeline-contract.md").read_text(encoding="utf-8")
    for workflow in WORKFLOWS:
        if f"`{workflow}`" not in text:
            fail(f"pipeline-contract.md does not mention {workflow}")


def main() -> int:
    require_files()
    validate_schema_files()
    validate_test_samplesheets()
    validate_presets()
    validate_contract_doc()
    print("ok - pipeline contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
