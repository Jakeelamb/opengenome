#!/usr/bin/env python3
"""Compile Open Genome pipeline artifacts into static HTML/TSV/JSON."""
from __future__ import annotations

import argparse
import csv
import html
import json
import os
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path


def _private_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def _private_open_csv(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    return os.fdopen(fd, "w", encoding="utf-8", newline="")


def _count_rows(path: Path) -> int:
    if not path.is_file():
        return 0
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        lines = [line for line in fh if line.strip() and not line.startswith("#")]
    if lines and lines[0].lower().startswith(("chrom\t", "sample\t", "row_id\t")):
        return max(0, len(lines) - 1)
    return len(lines)


def _read_samples(samplesheet: Path) -> list[dict[str, str]]:
    if not samplesheet.is_file():
        return []
    with samplesheet.open("r", encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    for row in rows:
        row.setdefault("row_id", row.get("sample", "unknown"))
        row.setdefault("lane", "lane_1")
    return rows


def _prefix(path: Path, suffix: str) -> str:
    name = path.name
    return name[: -len(suffix)] if name.endswith(suffix) else path.stem


def _read_status(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open("r", encoding="utf-8", newline="", errors="replace") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def _collect(input_dir: Path, samples: list[dict[str, str]]) -> dict:
    files = {
        "fastp": sorted(input_dir.rglob("fastp.*.json")),
        "fastqc": sorted(input_dir.rglob("*_fastqc.html")),
        "samtools_stats": sorted(input_dir.rglob("*.samtools.stats.txt")),
        "mosdepth": sorted(input_dir.rglob("*.mosdepth.summary.txt")),
        "vcf_stats": sorted(input_dir.rglob("*.bcftools.stats.txt")),
        "variant_tables": sorted(input_dir.rglob("*.variant_summary.tsv")),
        "clinvar_tables": sorted(input_dir.rglob("*.clinvar.matches.tsv")),
        "annotation_status": sorted(input_dir.rglob("*.annotation_status.tsv")),
        "pharmcat_status": sorted(input_dir.rglob("*.pharmcat_status.tsv")),
        "assembly_stats": sorted(input_dir.rglob("*.gfastats.txt")),
    }

    by_row: dict[str, dict] = defaultdict(lambda: {"files": defaultdict(list), "counts": defaultdict(int), "statuses": []})
    row_to_sample = {row.get("row_id") or row.get("sample", "unknown"): row.get("sample", "unknown") for row in samples}
    for row_id, sample in row_to_sample.items():
        by_row[row_id]["sample"] = sample
        by_row[row_id]["row_id"] = row_id

    suffixes = {
        "fastp": (".json", "fastp."),
        "samtools_stats": (".samtools.stats.txt", ""),
        "mosdepth": (".mosdepth.summary.txt", ""),
        "vcf_stats": (".bcftools.stats.txt", ""),
        "variant_tables": (".variant_summary.tsv", ""),
        "clinvar_tables": (".clinvar.matches.tsv", ""),
        "annotation_status": (".annotation_status.tsv", ""),
        "pharmcat_status": (".pharmcat_status.tsv", ""),
        "assembly_stats": (".gfastats.txt", ""),
    }

    for key, paths in files.items():
        if key == "fastqc":
            for path in paths:
                row_id = path.name.split("_fastqc.html", 1)[0].removesuffix(".trimmed.R1").removesuffix(".trimmed.R2")
                by_row[row_id]["files"][key].append(str(path))
            continue
        suffix, prefix = suffixes.get(key, ("", ""))
        for path in paths:
            name = path.name.removeprefix(prefix)
            row_id = _prefix(Path(name), suffix)
            by_row[row_id]["files"][key].append(str(path))
            if key == "variant_tables":
                by_row[row_id]["counts"]["variant_rows"] += _count_rows(path)
            elif key == "clinvar_tables":
                by_row[row_id]["counts"]["clinvar_rows"] += _count_rows(path)
            elif key == "assembly_stats":
                by_row[row_id]["counts"]["assembly_reports"] += 1
            elif key in {"annotation_status", "pharmcat_status"}:
                by_row[row_id]["statuses"].extend(_read_status(path))

    rows = []
    for row_id in sorted(by_row):
        item = by_row[row_id]
        item["files"] = {key: value for key, value in sorted(item["files"].items())}
        item["counts"] = {
            "variant_rows": int(item["counts"].get("variant_rows", 0)),
            "clinvar_rows": int(item["counts"].get("clinvar_rows", 0)),
            "assembly_reports": int(item["counts"].get("assembly_reports", 0)),
        }
        rows.append(item)

    return {
        "files": {key: [str(path) for path in value] for key, value in files.items()},
        "rows": rows,
        "counts": {
            "variant_rows": sum(row["counts"]["variant_rows"] for row in rows),
            "clinvar_rows": sum(row["counts"]["clinvar_rows"] for row in rows),
            "assembly_reports": sum(row["counts"]["assembly_reports"] for row in rows),
        },
    }


def _write_findings(path: Path, samples: list[dict[str, str]], evidence: dict) -> None:
    counts_by_row = {row["row_id"]: row["counts"] for row in evidence["rows"]}
    status_by_row = {row["row_id"]: row.get("statuses", []) for row in evidence["rows"]}
    with _private_open_csv(path) as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(["sample", "row_id", "finding", "source", "count", "what_this_does_not_mean"])
        for sample in samples or [{"sample": "unknown", "row_id": "unknown"}]:
            sample_id = sample.get("sample", "unknown")
            row_id = sample.get("row_id") or sample_id
            counts = counts_by_row.get(row_id, {})
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Variants normalized and summarized",
                    "bcftools",
                    counts.get("variant_rows", 0),
                    "This is not a diagnosis and does not imply disease risk by itself.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "ClinVar overlap table generated",
                    "ClinVar",
                    counts.get("clinvar_rows", 0),
                    "A match requires review by classification, review status, date, and clinical context.",
                ]
            )
            for status in status_by_row.get(row_id, []):
                if status.get("step") == "clinvar" or "state" in status:
                    writer.writerow(
                        [
                            sample_id,
                            row_id,
                            f"{status.get('step', 'PGx')} {status.get('state', 'unknown')}",
                            "pipeline-status",
                            "",
                            status.get("message", "Review status before interpretation."),
                        ]
                    )


def _write_html(path: Path, samples: list[dict[str, str]], evidence: dict, args: argparse.Namespace) -> None:
    rows = []
    evidence_by_row = {row["row_id"]: row for row in evidence["rows"]}
    for sample in samples or [{"sample": "unknown", "row_id": "unknown", "input_type": "unknown"}]:
        row_id = sample.get("row_id") or sample.get("sample", "unknown")
        row = evidence_by_row.get(row_id, {"counts": {}, "statuses": []})
        statuses = "; ".join(
            f"{status.get('step', 'PGx')}={status.get('state', 'unknown')}" for status in row.get("statuses", [])
        )
        rows.append(
            "<tr>"
            f"<td>{html.escape(sample.get('sample', 'unknown'))}</td>"
            f"<td>{html.escape(row_id)}</td>"
            f"<td>{html.escape(sample.get('input_type', 'unknown'))}</td>"
            f"<td>{html.escape(sample.get('sex', 'NA') or 'NA')}</td>"
            f"<td>{row.get('counts', {}).get('variant_rows', 0)}</td>"
            f"<td>{row.get('counts', {}).get('clinvar_rows', 0)}</td>"
            f"<td>{html.escape(statuses or 'not assessed')}</td>"
            "</tr>"
        )

    body = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Open Genome Report</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 1080px; margin: 2rem auto; line-height: 1.45; }}
    table {{ border-collapse: collapse; width: 100%; margin: 1rem 0; }}
    th, td {{ border: 1px solid #ccc; padding: 0.4rem 0.5rem; text-align: left; vertical-align: top; }}
    .warn {{ border-left: 4px solid #b35c00; padding-left: 1rem; }}
    code {{ background: #f3f3f3; padding: 0.1rem 0.25rem; }}
  </style>
</head>
<body>
  <h1>Open Genome Report</h1>
  <p>Generated {datetime.now(UTC).strftime('%Y-%m-%dT%H:%M:%SZ')} from local files.</p>
  <section class="warn">
    <h2>Boundary</h2>
    <p>This report is evidence, not diagnosis or treatment advice. Negative results do not remove genetic risk.</p>
  </section>
  <h2>Samples</h2>
  <table><thead><tr><th>Sample</th><th>Row ID</th><th>Input type</th><th>Sex</th><th>Variants</th><th>ClinVar rows</th><th>Status</th></tr></thead><tbody>{''.join(rows)}</tbody></table>
  <h2>Evidence Summary</h2>
  <table>
    <tr><th>Variants summarized</th><td>{evidence['counts']['variant_rows']}</td></tr>
    <tr><th>ClinVar overlap rows</th><td>{evidence['counts']['clinvar_rows']}</td></tr>
    <tr><th>Assembly reports</th><td>{evidence['counts']['assembly_reports']}</td></tr>
    <tr><th>Reference</th><td><code>{html.escape(args.reference or '')}</code></td></tr>
    <tr><th>ClinVar source</th><td><code>{html.escape(args.clinvar or '')}</code></td></tr>
    <tr><th>dbSNP source</th><td><code>{html.escape(args.dbsnp or '')}</code></td></tr>
    <tr><th>PharmCAT jar</th><td><code>{html.escape(args.pharmcat_jar or '')}</code></td></tr>
  </table>
  <h2>Files</h2>
  <p>Raw evidence tables are next to this report: <code>findings.tsv</code>, <code>evidence.json</code>, and <code>run_manifest.json</code>.</p>
</body>
</html>
"""
    _private_write(path, body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--samplesheet", type=Path, required=True)
    parser.add_argument("--reference", default="")
    parser.add_argument("--clinvar", default="")
    parser.add_argument("--dbsnp", default="")
    parser.add_argument("--pharmcat-jar", default="")
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.out_dir.chmod(0o700)
    samples = _read_samples(args.samplesheet)
    evidence = _collect(args.input_dir, samples)
    evidence["samples"] = samples
    evidence["generated_utc"] = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")

    _private_write(args.out_dir / "evidence.json", json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    _write_findings(args.out_dir / "findings.tsv", samples, evidence)
    _write_html(args.out_dir / "open_genome_report.html", samples, evidence, args)
    manifest = {
        "generated_utc": evidence["generated_utc"],
        "samplesheet": str(args.samplesheet),
        "reference": args.reference,
        "clinvar": args.clinvar,
        "dbsnp": args.dbsnp,
        "pharmcat_jar": args.pharmcat_jar,
    }
    _private_write(args.out_dir / "run_manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
