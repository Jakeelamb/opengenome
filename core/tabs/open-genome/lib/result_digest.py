#!/usr/bin/env python3
"""Render a terminal-friendly digest from Open Genome evidence files."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


def _int(value: Any) -> int:
    try:
        return int(float(str(value)))
    except (TypeError, ValueError):
        return 0


def _float(value: Any) -> float:
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return 0.0


def _fmt_float(value: float) -> str:
    return f"{value:.1f}".rstrip("0").rstrip(".")


def _plural(count: int, singular: str, plural: str | None = None) -> str:
    word = singular if count == 1 else (plural or f"{singular}s")
    return f"{count} {word}"


def _sum_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    keys = (
        "variant_rows",
        "snp_rows",
        "indel_rows",
        "mnv_rows",
        "symbolic_rows",
        "mitochondrial_variant_rows",
        "clinvar_rows",
        "public_annotation_rows",
        "consequence_rows",
        "covered_chromosomes",
        "coverage_breadth_reports",
        "qc_reports",
        "assembly_reports",
    )
    totals = {key: 0 for key in keys}
    for row in rows:
        counts = row.get("counts", {})
        if not isinstance(counts, dict):
            continue
        for key in keys:
            totals[key] += _int(counts.get(key))
    return totals


def _coverage_total(row: dict[str, Any]) -> dict[str, Any]:
    for item in row.get("coverage", []) if isinstance(row.get("coverage"), list) else []:
        if isinstance(item, dict) and isinstance(item.get("total"), dict):
            return item["total"]
    return {}


def _breadth_total(row: dict[str, Any]) -> dict[str, Any]:
    for item in row.get("coverage_breadth", []) if isinstance(row.get("coverage_breadth"), list) else []:
        if isinstance(item, dict) and isinstance(item.get("total"), dict):
            return item["total"]
    return {}


def _threshold_pct(row: dict[str, Any], threshold: int) -> float:
    total = _breadth_total(row)
    thresholds = total.get("thresholds", {}) if isinstance(total, dict) else {}
    value = thresholds.get(str(threshold), {}) if isinstance(thresholds, dict) else {}
    if isinstance(value, dict):
        return _float(value.get("pct"))
    return 0.0


def _mean_depth(rows: list[dict[str, Any]]) -> float:
    means = []
    for row in rows:
        total = _coverage_total(row)
        mean = _float(total.get("mean")) if isinstance(total, dict) else 0.0
        if mean > 0:
            means.append(mean)
    if not means:
        return 0.0
    return sum(means) / len(means)


def _mean_threshold(rows: list[dict[str, Any]], threshold: int) -> float:
    values = [_threshold_pct(row, threshold) for row in rows]
    values = [value for value in values if value > 0]
    if not values:
        return 0.0
    return sum(values) / len(values)


def _readiness_label(rows: list[dict[str, Any]], totals: dict[str, int]) -> str:
    mean_depth = _mean_depth(rows)
    breadth_20 = _mean_threshold(rows, 20)
    if totals.get("variant_rows", 0) and mean_depth >= 30 and breadth_20 >= 90:
        return "high-confidence review set"
    if totals.get("variant_rows", 0):
        return "reviewable evidence set"
    return "incomplete evidence set"


def _input_types(samples: list[dict[str, Any]]) -> str:
    counts: dict[str, int] = {}
    for sample in samples:
        kind = str(sample.get("input_type") or "unknown")
        counts[kind] = counts.get(kind, 0) + 1
    if not counts:
        return "unknown"
    return ", ".join(f"{kind}={count}" for kind, count in sorted(counts.items()))


def _sample_names(samples: list[dict[str, Any]], rows: list[dict[str, Any]]) -> str:
    names = [str(sample.get("sample") or sample.get("row_id") or "").strip() for sample in samples]
    if not names:
        names = [str(row.get("sample") or row.get("row_id") or "").strip() for row in rows]
    names = [name for name in names if name]
    if not names:
        return "unknown"
    if len(names) <= 3:
        return ", ".join(names)
    return ", ".join(names[:3]) + f", +{len(names) - 3} more"


def _finding_sections(path: Path | None) -> list[str]:
    if path is None or not path.is_file():
        return []
    sections: dict[str, int] = {}
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            section = (row.get("section") or "").strip()
            if not section:
                continue
            sections[section] = sections.get(section, 0) + 1
    return [f"{name} ({count})" for name, count in sorted(sections.items())]


def render_digest(evidence_path: Path, findings_path: Path | None = None) -> str:
    data = json.loads(evidence_path.read_text(encoding="utf-8"))
    rows = data.get("rows", [])
    samples = data.get("samples", [])
    if not isinstance(rows, list):
        rows = []
    if not isinstance(samples, list):
        samples = []
    totals = data.get("counts") if isinstance(data.get("counts"), dict) else _sum_counts(rows)
    totals = {key: _int(value) for key, value in totals.items()}

    sample_count = len(samples) or len(rows)
    lines = [
        "Report snapshot",
        f"  Samples: {sample_count} ({_input_types(samples)})",
        f"  Sample IDs: {_sample_names(samples, rows)}",
        f"  Readiness: {_readiness_label(rows, totals)}",
        (
            "  Variants: "
            f"{_plural(totals.get('variant_rows', 0), 'total row')}; "
            f"{_plural(totals.get('snp_rows', 0), 'SNP')}; "
            f"{_plural(totals.get('indel_rows', 0), 'indel')}; "
            f"{_plural(totals.get('mitochondrial_variant_rows', 0), 'mtDNA variant')}"
        ),
    ]

    mean_depth = _mean_depth(rows)
    breadth_10 = _mean_threshold(rows, 10)
    breadth_20 = _mean_threshold(rows, 20)
    breadth_30 = _mean_threshold(rows, 30)
    if mean_depth or breadth_10:
        lines.append(
            "  Coverage: "
            f"mean depth {_fmt_float(mean_depth)}x; "
            f">=10x breadth {_fmt_float(breadth_10)}%; "
            f">=20x {_fmt_float(breadth_20)}%; "
            f">=30x {_fmt_float(breadth_30)}%"
        )
    else:
        lines.append("  Coverage: no mosdepth summary found")

    lines.extend(
        [
            (
                "  Public evidence: "
                f"{_plural(totals.get('clinvar_rows', 0), 'ClinVar row')}; "
                f"{_plural(totals.get('public_annotation_rows', 0), 'dbSNP/gnomAD row')}; "
                f"{_plural(totals.get('consequence_rows', 0), 'consequence row')}"
            ),
            (
                "  QC artifacts: "
                f"{_plural(totals.get('qc_reports', 0), 'FastQC/fastp report')}; "
                f"{_plural(len(data.get('files', {}).get('multiqc', [])) if isinstance(data.get('files'), dict) else 0, 'MultiQC report')}"
            ),
            f"  Assembly continuity reports: {totals.get('assembly_reports', 0)}",
        ]
    )

    lines.extend(
        [
            "",
            "Report style",
            "  Publication-style: depth, breadth, variant classes, mtDNA, assembly continuity, and resource provenance.",
            "  Consumer-style: plain-language evidence summaries with explicit limits before interpretation.",
        ]
    )

    sections = _finding_sections(findings_path)
    if sections:
        lines.extend(["", "Finding sections", "  " + "; ".join(sections[:8])])

    lines.extend(
        [
            "",
            "Interpretation guardrails",
            "  This is an evidence inventory, not a diagnosis or treatment recommendation.",
            "  Public database matches need review for classification, date, review status, frequency, and clinical context.",
            "  Empty sections usually mean the matching local resource or workflow output was not configured or generated.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--findings", type=Path, default=None)
    args = parser.parse_args()
    print(render_digest(args.evidence, args.findings), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
