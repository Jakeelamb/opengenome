#!/usr/bin/env python3
"""Compile Open Genome pipeline artifacts into static HTML/TSV/JSON."""
from __future__ import annotations

import argparse
import csv
import gzip
import html
import json
import os
import re
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterable


PUBLIC_ANNOTATION_PREVIEW_LIMIT = 200
MOSDEPTH_THRESHOLDS = (1, 10, 20, 30)


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


def _safe_int(value: object, default: int = 0) -> int:
    try:
        return int(float(str(value).strip()))
    except (TypeError, ValueError):
        return default


def _safe_float(value: object, default: float = 0.0) -> float:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return default


def _fmt_number(value: object) -> str:
    if isinstance(value, float):
        return f"{value:.2f}".rstrip("0").rstrip(".")
    if isinstance(value, int):
        return f"{value:,}"
    return html.escape(str(value or ""))


def _count_rows(path: Path) -> int:
    if not path.is_file():
        return 0
    count = 0
    with _open_text(path) as fh:
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue
            if count == 0 and line.lower().startswith(("chrom\t", "sample\t", "row_id\t")):
                continue
            count += 1
    return count


def _open_text(path: Path):
    if path.name.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return path.open("r", encoding="utf-8", errors="replace")


def _is_mito_chrom(chrom: str) -> bool:
    value = re.sub(r"[^A-Za-z0-9]+", "", chrom).lower()
    return value in {"m", "mt", "chrm", "chrmt", "mitochondria", "mitochondrion"}


def _variant_kind(ref: str, alt: str) -> str:
    alts = [part for part in alt.split(",") if part and part != "."]
    if not alts:
        return "other"
    if any(part.startswith("<") or "[" in part or "]" in part for part in alts):
        return "symbolic"
    if len(ref) == 1 and all(len(part) == 1 for part in alts):
        return "snp"
    if any(len(part) != len(ref) for part in alts):
        return "indel"
    if len(ref) > 1 and all(len(part) == len(ref) for part in alts):
        return "mnv"
    return "other"


def _summarize_variant_table(path: Path) -> dict[str, object]:
    counts = defaultdict(int)
    mito_counts = defaultdict(int)
    with _open_text(path) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        if not reader.fieldnames:
            return {"total": 0, "classes": {}, "mitochondrial": {}}
        for row in reader:
            if not row:
                continue
            kind = _variant_kind(row.get("ref", ""), row.get("alt", ""))
            counts["total"] += 1
            counts[kind] += 1
            if _is_mito_chrom(row.get("chrom", "")):
                mito_counts["total"] += 1
                mito_counts[kind] += 1
    return {
        "total": int(counts.get("total", 0)),
        "classes": {key: int(value) for key, value in sorted(counts.items()) if key != "total"},
        "mitochondrial": {key: int(value) for key, value in sorted(mito_counts.items())},
    }


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


def _read_tsv(path: Path, limit: int | None = None) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with _open_text(path) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        if not reader.fieldnames:
            return []
        rows = []
        for idx, row in enumerate(reader):
            if limit is not None and idx >= limit:
                break
            rows.append(dict(row))
        return rows


def _read_status(path: Path) -> list[dict[str, str]]:
    return _read_tsv(path)


def _read_fastp_json(path: Path) -> dict[str, object]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"file": str(path), "state": "unreadable"}
    summary = data.get("summary", {}) if isinstance(data, dict) else {}
    before = summary.get("before_filtering", {}) if isinstance(summary, dict) else {}
    after = summary.get("after_filtering", {}) if isinstance(summary, dict) else {}
    return {
        "file": str(path),
        "state": "parsed",
        "reads_before": _safe_int(before.get("total_reads")),
        "reads_after": _safe_int(after.get("total_reads")),
        "bases_after": _safe_int(after.get("total_bases")),
        "q30_rate_after": _safe_float(after.get("q30_rate")),
    }


def _parse_mosdepth_summary(path: Path) -> dict[str, object]:
    rows: list[dict[str, object]] = []
    total_row: dict[str, object] | None = None
    for row in _read_tsv(path):
        chrom = (row.get("chrom") or row.get("#chrom") or "").strip()
        if not chrom:
            continue
        parsed = {
            "chrom": chrom,
            "length": _safe_int(row.get("length")),
            "bases": _safe_float(row.get("bases")),
            "mean": _safe_float(row.get("mean")),
            "min": _safe_float(row.get("min")),
            "max": _safe_float(row.get("max")),
        }
        if chrom.lower() in {"total", "genome"}:
            total_row = parsed
        else:
            rows.append(parsed)
    if total_row is None and rows:
        length = sum(_safe_int(row.get("length")) for row in rows)
        bases = sum(_safe_float(row.get("bases")) for row in rows)
        total_row = {
            "chrom": "total",
            "length": length,
            "bases": bases,
            "mean": bases / length if length else 0.0,
            "min": min(_safe_float(row.get("min")) for row in rows),
            "max": max(_safe_float(row.get("max")) for row in rows),
        }
    return {"file": str(path), "chromosomes": rows, "total": total_row or {}}


def _parse_mosdepth_thresholds(path: Path) -> dict[str, object]:
    by_chrom: dict[str, dict[str, object]] = {}
    totals = {threshold: 0 for threshold in MOSDEPTH_THRESHOLDS}
    total_length = 0
    with _open_text(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 3:
                continue
            chrom = fields[0]
            start = _safe_int(fields[1])
            end = _safe_int(fields[2])
            length = max(0, end - start)
            if length <= 0:
                continue
            numeric_tail: list[int] = []
            for value in reversed(fields[3:]):
                try:
                    numeric_tail.append(int(float(value)))
                except ValueError:
                    break
                if len(numeric_tail) == len(MOSDEPTH_THRESHOLDS):
                    break
            if len(numeric_tail) != len(MOSDEPTH_THRESHOLDS):
                continue
            threshold_counts = dict(zip(MOSDEPTH_THRESHOLDS, reversed(numeric_tail), strict=True))
            item = by_chrom.setdefault(chrom, {"chrom": chrom, "length": 0, "thresholds": {t: 0 for t in MOSDEPTH_THRESHOLDS}})
            item["length"] = _safe_int(item["length"]) + length
            total_length += length
            for threshold, covered in threshold_counts.items():
                item["thresholds"][threshold] += covered
                totals[threshold] += covered

    def with_pct(item: dict[str, object]) -> dict[str, object]:
        length = _safe_int(item.get("length"))
        thresholds = item.get("thresholds", {})
        return {
            "chrom": item.get("chrom", ""),
            "length": length,
            "thresholds": {
                str(threshold): {
                    "bases": _safe_int(thresholds.get(threshold, 0)),
                    "pct": (_safe_int(thresholds.get(threshold, 0)) / length * 100.0) if length else 0.0,
                }
                for threshold in MOSDEPTH_THRESHOLDS
            },
        }

    total_item = with_pct({"chrom": "total", "length": total_length, "thresholds": totals})
    chrom_items = [with_pct(item) for _, item in sorted(by_chrom.items())]
    return {"file": str(path), "chromosomes": chrom_items, "total": total_item}


def _parse_assembly_stats(path: Path) -> dict[str, object]:
    metrics: list[dict[str, str]] = []
    wanted = ("n50", "n90", "auN", "ng50", "total", "scaffold", "contig")
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        lower = line.lower()
        if not any(token.lower() in lower for token in wanted):
            continue
        if ":" in line:
            key, value = line.split(":", 1)
        elif "\t" in line:
            key, value = line.split("\t", 1)
        else:
            parts = re.split(r"\s{2,}", line, maxsplit=1)
            key, value = (parts + [""])[:2]
        metrics.append({"metric": key.strip(), "value": value.strip()})
    return {"file": str(path), "metrics": metrics[:12]}


def _relative_link(path: str | Path, out_dir: Path) -> str:
    p = Path(path)
    try:
        return os.path.relpath(p.resolve(), out_dir.resolve())
    except OSError:
        return str(path)


def _file_anchor(path: str | Path, out_dir: Path, label: str | None = None) -> str:
    href = _relative_link(path, out_dir)
    text = label or Path(path).name
    return f'<a href="{html.escape(href, quote=True)}">{html.escape(text)}</a>'


def _image_preview(path: str | Path, out_dir: Path, alt: str) -> str:
    href = _relative_link(path, out_dir)
    escaped_href = html.escape(href, quote=True)
    return (
        f'<figure class="viz-preview">'
        f'<a href="{escaped_href}"><img src="{escaped_href}" alt="{html.escape(alt, quote=True)}" loading="lazy"></a>'
        f'<figcaption>{html.escape(Path(path).name)}</figcaption>'
        f'</figure>'
    )


def _row_id_from_fastqc(path: Path) -> str:
    name = path.name.split("_fastqc.html", 1)[0]
    for suffix in (".trimmed.R1", ".trimmed.R2", ".R1", ".R2", "_R1", "_R2"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def _row_id_from_read_density(path: Path) -> str:
    for suffix in (".read_density.svg", ".read_density.png"):
        if path.name.endswith(suffix):
            return _prefix(path, suffix)
    return path.stem


def _collect(input_dir: Path, samples: list[dict[str, str]]) -> dict:
    files = {
        "fastp_json": sorted(input_dir.rglob("fastp.*.json")),
        "fastp_html": sorted(input_dir.rglob("fastp.*.html")),
        "fastqc": sorted(input_dir.rglob("*_fastqc.html")),
        "multiqc": sorted(input_dir.rglob("*multiqc_report.html")),
        "read_density_plots": sorted(input_dir.rglob("*.read_density.svg")) + sorted(input_dir.rglob("*.read_density.png")),
        "samtools_stats": sorted(input_dir.rglob("*.samtools.stats.txt")),
        "long_read_stats": sorted(input_dir.rglob("*.long_reads.seqkit_stats.tsv")),
        "long_read_alignment_status": sorted(input_dir.rglob("*.long_read_alignment_status.tsv")),
        "mosdepth": sorted(input_dir.rglob("*.mosdepth.summary.txt")),
        "mosdepth_thresholds": sorted(input_dir.rglob("*.thresholds.bed.gz")),
        "vcf_stats": sorted(input_dir.rglob("*.bcftools.stats.txt")),
        "variant_tables": sorted(input_dir.rglob("*.variant_summary.tsv")),
        "clinvar_tables": sorted(input_dir.rglob("*.clinvar.matches.tsv")),
        "public_annotations": sorted(input_dir.rglob("*.public_annotations.tsv")),
        "consequence_summary": sorted(input_dir.rglob("*.consequence_summary.tsv")),
        "consequence_status": sorted(input_dir.rglob("*.consequence_status.tsv")),
        "annotation_status": sorted(input_dir.rglob("*.annotation_status.tsv")),
        "variant_caller_status": sorted(input_dir.rglob("*.variant_caller_status.tsv")),
        "pharmcat_status": sorted(input_dir.rglob("*.pharmcat_status.tsv")),
        "assembly_stats": sorted(input_dir.rglob("*.gfastats.txt")),
        "mito_status": sorted(input_dir.rglob("*.mitochondrial_status.tsv")),
        "mito_consensus": sorted(input_dir.rglob("*.mitochondrial_consensus.fa")),
    }

    by_row: dict[str, dict] = defaultdict(
        lambda: {
            "files": defaultdict(list),
            "counts": defaultdict(int),
            "statuses": [],
            "qc": [],
            "coverage": [],
            "coverage_breadth": [],
            "variant_summary": {"total": 0, "classes": {}, "mitochondrial": {}},
            "public_annotations": [],
            "consequences": [],
            "assembly": [],
            "mitochondria": {"statuses": [], "consensus": []},
        }
    )
    row_to_sample = {row.get("row_id") or row.get("sample", "unknown"): row.get("sample", "unknown") for row in samples}
    for row_id, sample in row_to_sample.items():
        by_row[row_id]["sample"] = sample
        by_row[row_id]["row_id"] = row_id

    suffixes = {
        "fastp_json": (".json", "fastp."),
        "fastp_html": (".html", "fastp."),
        "read_density_plots": (".read_density.svg", ""),
        "samtools_stats": (".samtools.stats.txt", ""),
        "long_read_stats": (".long_reads.seqkit_stats.tsv", ""),
        "long_read_alignment_status": (".long_read_alignment_status.tsv", ""),
        "mosdepth": (".mosdepth.summary.txt", ""),
        "mosdepth_thresholds": (".thresholds.bed.gz", ""),
        "vcf_stats": (".bcftools.stats.txt", ""),
        "variant_tables": (".variant_summary.tsv", ""),
        "clinvar_tables": (".clinvar.matches.tsv", ""),
        "public_annotations": (".public_annotations.tsv", ""),
        "consequence_summary": (".consequence_summary.tsv", ""),
        "consequence_status": (".consequence_status.tsv", ""),
        "annotation_status": (".annotation_status.tsv", ""),
        "variant_caller_status": (".variant_caller_status.tsv", ""),
        "pharmcat_status": (".pharmcat_status.tsv", ""),
        "assembly_stats": (".gfastats.txt", ""),
        "mito_status": (".mitochondrial_status.tsv", ""),
        "mito_consensus": (".mitochondrial_consensus.fa", ""),
    }

    for key, paths in files.items():
        if key == "multiqc":
            continue
        if key == "fastqc":
            for path in paths:
                row_id = _row_id_from_fastqc(path)
                by_row[row_id]["row_id"] = row_id
                by_row[row_id]["files"][key].append(str(path))
                by_row[row_id]["counts"]["qc_reports"] += 1
            continue
        if key == "read_density_plots":
            for path in paths:
                row_id = _row_id_from_read_density(path)
                by_row[row_id]["row_id"] = row_id
                by_row[row_id].setdefault("sample", row_to_sample.get(row_id, row_id))
                by_row[row_id]["files"][key].append(str(path))
                by_row[row_id]["counts"]["coverage_density_plots"] += 1
            continue
        suffix, prefix = suffixes.get(key, ("", ""))
        for path in paths:
            name = path.name.removeprefix(prefix)
            row_id = _prefix(Path(name), suffix)
            by_row[row_id]["row_id"] = row_id
            by_row[row_id].setdefault("sample", row_to_sample.get(row_id, row_id))
            by_row[row_id]["files"][key].append(str(path))
            if key == "fastp_json":
                by_row[row_id]["qc"].append(_read_fastp_json(path))
                by_row[row_id]["counts"]["qc_reports"] += 1
            elif key == "fastp_html":
                by_row[row_id]["counts"]["qc_reports"] += 1
            elif key == "mosdepth":
                coverage = _parse_mosdepth_summary(path)
                by_row[row_id]["coverage"].append(coverage)
                by_row[row_id]["counts"]["covered_chromosomes"] += len(coverage["chromosomes"])
            elif key == "mosdepth_thresholds":
                breadth = _parse_mosdepth_thresholds(path)
                by_row[row_id]["coverage_breadth"].append(breadth)
                by_row[row_id]["counts"]["coverage_breadth_reports"] += 1
            elif key == "variant_tables":
                summary = _summarize_variant_table(path)
                by_row[row_id]["variant_summary"] = summary
                by_row[row_id]["counts"]["variant_rows"] += int(summary.get("total", 0))
                classes = summary.get("classes", {})
                by_row[row_id]["counts"]["snp_rows"] += int(classes.get("snp", 0))
                by_row[row_id]["counts"]["indel_rows"] += int(classes.get("indel", 0))
                by_row[row_id]["counts"]["mnv_rows"] += int(classes.get("mnv", 0))
                by_row[row_id]["counts"]["symbolic_rows"] += int(classes.get("symbolic", 0))
                mito = summary.get("mitochondrial", {})
                by_row[row_id]["counts"]["mitochondrial_variant_rows"] += int(mito.get("total", 0))
                by_row[row_id]["counts"]["mitochondrial_snp_rows"] += int(mito.get("snp", 0))
                by_row[row_id]["counts"]["mitochondrial_indel_rows"] += int(mito.get("indel", 0))
            elif key == "clinvar_tables":
                by_row[row_id]["counts"]["clinvar_rows"] += _count_rows(path)
            elif key == "public_annotations":
                rows = _read_tsv(path, limit=PUBLIC_ANNOTATION_PREVIEW_LIMIT)
                by_row[row_id]["public_annotations"].extend(rows)
                by_row[row_id]["counts"]["public_annotation_rows"] += _count_rows(path)
            elif key == "consequence_summary":
                rows = _read_tsv(path)
                by_row[row_id]["consequences"].extend(rows)
                by_row[row_id]["counts"]["consequence_rows"] += sum(1 for row in rows if _safe_int(row.get("count")) > 0)
            elif key == "assembly_stats":
                by_row[row_id]["assembly"].append(_parse_assembly_stats(path))
                by_row[row_id]["counts"]["assembly_reports"] += 1
            elif key == "mito_status":
                by_row[row_id]["mitochondria"]["statuses"].extend(_read_status(path))
            elif key == "mito_consensus":
                by_row[row_id]["mitochondria"]["consensus"].append(str(path))
            elif key == "long_read_stats":
                by_row[row_id]["counts"]["long_read_qc_reports"] += 1
            elif key in {"annotation_status", "pharmcat_status", "consequence_status", "variant_caller_status", "long_read_alignment_status"}:
                by_row[row_id]["statuses"].extend(_read_status(path))

    rows = []
    for row_id in sorted(by_row):
        item = by_row[row_id]
        item["files"] = {key: value for key, value in sorted(item["files"].items())}
        item["counts"] = {
            "variant_rows": int(item["counts"].get("variant_rows", 0)),
            "snp_rows": int(item["counts"].get("snp_rows", 0)),
            "indel_rows": int(item["counts"].get("indel_rows", 0)),
            "mnv_rows": int(item["counts"].get("mnv_rows", 0)),
            "symbolic_rows": int(item["counts"].get("symbolic_rows", 0)),
            "mitochondrial_variant_rows": int(item["counts"].get("mitochondrial_variant_rows", 0)),
            "mitochondrial_snp_rows": int(item["counts"].get("mitochondrial_snp_rows", 0)),
            "mitochondrial_indel_rows": int(item["counts"].get("mitochondrial_indel_rows", 0)),
            "clinvar_rows": int(item["counts"].get("clinvar_rows", 0)),
            "public_annotation_rows": int(item["counts"].get("public_annotation_rows", 0)),
            "consequence_rows": int(item["counts"].get("consequence_rows", 0)),
            "covered_chromosomes": int(item["counts"].get("covered_chromosomes", 0)),
            "coverage_breadth_reports": int(item["counts"].get("coverage_breadth_reports", 0)),
            "coverage_density_plots": int(item["counts"].get("coverage_density_plots", 0)),
            "qc_reports": int(item["counts"].get("qc_reports", 0)),
            "long_read_qc_reports": int(item["counts"].get("long_read_qc_reports", 0)),
            "assembly_reports": int(item["counts"].get("assembly_reports", 0)),
        }
        rows.append(item)

    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        for key, value in row["counts"].items():
            counts[key] += int(value)

    return {
        "files": {key: [str(path) for path in value] for key, value in files.items()},
        "rows": rows,
        "counts": dict(counts),
    }


def _write_findings(path: Path, samples: list[dict[str, str]], evidence: dict) -> None:
    counts_by_row = {row["row_id"]: row["counts"] for row in evidence["rows"]}
    status_by_row = {row["row_id"]: row.get("statuses", []) for row in evidence["rows"]}
    with _private_open_csv(path) as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(
            [
                "sample",
                "row_id",
                "section",
                "finding",
                "source",
                "count",
                "what_this_means",
                "what_this_does_not_mean",
            ]
        )
        for sample in samples or [{"sample": "unknown", "row_id": "unknown"}]:
            sample_id = sample.get("sample", "unknown")
            row_id = sample.get("row_id") or sample_id
            counts = counts_by_row.get(row_id, {})
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Variants",
                    "Variants normalized and summarized",
                    "bcftools",
                    counts.get("variant_rows", 0),
                    "Variants were normalized into a reviewable evidence table.",
                    "This is not a diagnosis and does not imply disease risk by itself.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Variants",
                    "SNPs and indels classified",
                    "variant summary",
                    f"SNPs={counts.get('snp_rows', 0)}; indels={counts.get('indel_rows', 0)}",
                    "The report separates small variant classes so users can see whether the callset looks plausible for WGS.",
                    "Variant class counts are QC context, not clinical interpretation.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Coverage",
                    "Coverage summary generated",
                    "mosdepth",
                    counts.get("covered_chromosomes", 0),
                    "Read depth was summarized by reference sequence when alignments were available.",
                    "Coverage does not guarantee every clinically relevant region was confidently assessed.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Mitochondrial genome",
                    "Mitochondrial coverage and variants summarized",
                    "mosdepth/bcftools",
                    counts.get("mitochondrial_variant_rows", 0),
                    "mtDNA coverage and variant evidence were summarized when chrM/MT was present in the reference or VCF.",
                    "This is not haplogroup assignment, heteroplasmy validation, or a diagnosis.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Public annotation",
                    "ClinVar overlap table generated",
                    "ClinVar",
                    counts.get("clinvar_rows", 0),
                    "Variants overlapping the configured ClinVar VCF were listed for review.",
                    "A match requires review by classification, review status, date, and clinical context.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Public annotation",
                    "dbSNP/gnomAD annotation table generated",
                    "dbSNP/gnomAD",
                    counts.get("public_annotation_rows", 0),
                    "Known IDs and configured population-frequency overlaps were listed when local resources were present.",
                    "Population frequency is not disease prediction and can be ancestry/context dependent.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "Consequences",
                    "VEP/SnpEff consequence summary generated",
                    "ANN/CSQ",
                    counts.get("consequence_rows", 0),
                    "Existing VEP CSQ or SnpEff ANN consequence fields were summarized when present.",
                    "Consequence labels are computational predictions and need review against transcript choice and evidence.",
                ]
            )
            writer.writerow(
                [
                    sample_id,
                    row_id,
                    "PGx",
                    "PharmCAT status recorded",
                    "PharmCAT",
                    "",
                    "PGx was kept in a separate report section.",
                    "PGx output is not prescribing advice.",
                ]
            )
            for status in status_by_row.get(row_id, []):
                writer.writerow(
                    [
                        sample_id,
                        row_id,
                        status.get("step", "Status"),
                        f"{status.get('step', 'status')} {status.get('state', 'unknown')}",
                        "pipeline-status",
                        "",
                        status.get("message", "Review status before interpretation."),
                        "Skipped or missing optional resources mean that section was not fully assessed.",
                    ]
                )


def _html_table(headers: list[str], rows: Iterable[Iterable[object]], empty: str) -> str:
    body_rows = []
    for row in rows:
        body_rows.append("<tr>" + "".join(f"<td>{_fmt_number(value)}</td>" for value in row) + "</tr>")
    if not body_rows:
        return f'<p class="empty">{html.escape(empty)}</p>'
    header = "".join(f"<th>{html.escape(label)}</th>" for label in headers)
    return f"<table><thead><tr>{header}</tr></thead><tbody>{''.join(body_rows)}</tbody></table>"


def _coverage_chart(row: dict) -> str:
    coverage_sets = row.get("coverage", [])
    chrom_rows: list[dict[str, object]] = []
    for coverage in coverage_sets:
        chrom_rows.extend(coverage.get("chromosomes", []))
    chrom_rows = [item for item in chrom_rows if _safe_float(item.get("mean")) > 0][:28]
    if not chrom_rows:
        return '<p class="empty">No chromosome coverage chart is available for this sample.</p>'
    width = 920
    height = 280
    left = 48
    bottom = 44
    top = 20
    chart_h = height - bottom - top
    observed_max = max(_safe_float(item.get("mean")) for item in chrom_rows) or 1.0
    max_mean = max(30.0, observed_max)
    gap = 5
    bar_w = max(8, int((width - left - 24 - (len(chrom_rows) - 1) * gap) / len(chrom_rows)))
    parts = [
        f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="Chromosome coverage chart" class="coverage-chart">',
        f'<line x1="{left}" y1="{height-bottom}" x2="{width-16}" y2="{height-bottom}" class="axis" />',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{height-bottom}" class="axis" />',
        f'<text x="8" y="{top+8}" class="axis-label">{max_mean:.1f}x</text>',
    ]
    for idx, item in enumerate(chrom_rows):
        mean = _safe_float(item.get("mean"))
        bar_h = max(1, int(chart_h * mean / max_mean))
        x = left + 10 + idx * (bar_w + gap)
        y = height - bottom - bar_h
        chrom = str(item.get("chrom", ""))
        level = "good" if mean >= 20 else "warn" if mean >= 10 else "low"
        parts.append(f'<rect x="{x}" y="{y}" width="{bar_w}" height="{bar_h}" rx="2" class="bar {level}" />')
        parts.append(f'<title>{html.escape(chrom)}: {mean:.2f}x mean coverage</title>')
        if idx % 2 == 0 or len(chrom_rows) <= 16:
            parts.append(f'<text x="{x + bar_w / 2:.1f}" y="{height-18}" class="tick">{html.escape(chrom[:8])}</text>')
    for label, value in (("10x", 10.0), ("20x", 20.0), ("30x", 30.0)):
        if value > max_mean:
            continue
        y = height - bottom - int(chart_h * value / max_mean)
        parts.append(f'<line x1="{left}" y1="{y}" x2="{width-16}" y2="{y}" class="target-line" />')
        parts.append(f'<text x="{left + 6}" y="{y - 4}" class="target-label">{label}</text>')
    parts.append("</svg>")
    return "".join(parts)


def _variant_mix_chart(evidence: dict) -> str:
    counts = evidence.get("counts", {})
    total = _safe_int(counts.get("variant_rows"))
    if total <= 0:
        return '<p class="empty">No variant rows were available for variant mix visualization.</p>'
    classes = [
        ("SNP", _safe_int(counts.get("snp_rows")), "snp"),
        ("Indel", _safe_int(counts.get("indel_rows")), "indel"),
        ("MNV", _safe_int(counts.get("mnv_rows")), "mnv"),
        ("Symbolic / structural", _safe_int(counts.get("symbolic_rows")), "symbolic"),
    ]
    bars = []
    for label, value, css_class in classes:
        pct = value / total * 100.0 if total else 0.0
        if value <= 0:
            continue
        bars.append(f'<span class="{css_class}" style="width:{pct:.3f}%"><b>{html.escape(label)}</b> {_fmt_number(value)} ({pct:.1f}%)</span>')
    legend = "".join(
        f'<li><span class="swatch {css_class}"></span>{html.escape(label)}: {_fmt_number(value)}</li>'
        for label, value, css_class in classes
    )
    return f'<div class="variant-mix">{"".join(bars)}</div><ul class="legend">{legend}</ul>'


def _status_text(row: dict) -> str:
    statuses = []
    for status in row.get("statuses", []):
        step = status.get("step") or "PGx"
        state = status.get("state", "unknown")
        statuses.append(f"{step}: {state}")
    return "; ".join(statuses) or "not assessed"


def _coverage_total(row: dict) -> dict[str, object]:
    for coverage in row.get("coverage", []):
        total = coverage.get("total", {})
        if total:
            return total
    return {}


def _breadth_total(row: dict) -> dict[str, object]:
    for breadth in row.get("coverage_breadth", []):
        total = breadth.get("total", {})
        if total:
            return total
    return {}


def _threshold_pct(item: dict[str, object], threshold: int) -> float:
    thresholds = item.get("thresholds", {})
    value = thresholds.get(str(threshold), {}) if isinstance(thresholds, dict) else {}
    return _safe_float(value.get("pct")) if isinstance(value, dict) else 0.0


def _mito_coverage(row: dict) -> tuple[dict[str, object], dict[str, object]]:
    summary: dict[str, object] = {}
    breadth_summary: dict[str, object] = {}
    for coverage in row.get("coverage", []):
        for item in coverage.get("chromosomes", []):
            if _is_mito_chrom(str(item.get("chrom", ""))):
                summary = item
                break
        if summary:
            break
    for breadth in row.get("coverage_breadth", []):
        for item in breadth.get("chromosomes", []):
            if _is_mito_chrom(str(item.get("chrom", ""))):
                breadth_summary = item
                break
        if breadth_summary:
            break
    return summary, breadth_summary


def _sample_rows(samples: list[dict[str, str]], evidence: dict) -> list[list[object]]:
    evidence_by_row = {row["row_id"]: row for row in evidence["rows"]}
    rows = []
    for sample in samples or [{"sample": "unknown", "row_id": "unknown", "input_type": "unknown"}]:
        row_id = sample.get("row_id") or sample.get("sample", "unknown")
        row = evidence_by_row.get(row_id, {"counts": {}, "statuses": []})
        counts = row.get("counts", {})
        coverage = _coverage_total(row)
        breadth = _breadth_total(row)
        rows.append(
            [
                sample.get("sample", "unknown"),
                row_id,
                sample.get("input_type", "unknown"),
                sample.get("sex", "NA") or "NA",
                counts.get("qc_reports", 0),
                _safe_float(coverage.get("mean")),
                _threshold_pct(breadth, 10),
                counts.get("variant_rows", 0),
                counts.get("snp_rows", 0),
                counts.get("indel_rows", 0),
                counts.get("mitochondrial_variant_rows", 0),
                counts.get("clinvar_rows", 0),
                counts.get("public_annotation_rows", 0),
                counts.get("consequence_rows", 0),
                _status_text(row),
            ]
        )
    return rows


def _mean_depth_for_evidence(evidence: dict) -> float:
    means = []
    for row in evidence.get("rows", []):
        total = _coverage_total(row)
        mean = _safe_float(total.get("mean"))
        if mean > 0:
            means.append(mean)
    return sum(means) / len(means) if means else 0.0


def _mean_breadth_for_evidence(evidence: dict, threshold: int) -> float:
    values = []
    for row in evidence.get("rows", []):
        breadth = _breadth_total(row)
        value = _threshold_pct(breadth, threshold)
        if value > 0:
            values.append(value)
    return sum(values) / len(values) if values else 0.0


def _readiness_state(evidence: dict) -> tuple[str, str]:
    counts = evidence.get("counts", {})
    mean_depth = _mean_depth_for_evidence(evidence)
    breadth_20 = _mean_breadth_for_evidence(evidence, 20)
    if counts.get("variant_rows", 0) and mean_depth >= 30 and breadth_20 >= 90:
        return ("High-confidence review set", "Depth and breadth look suitable for a compact WGS evidence review.")
    if counts.get("variant_rows", 0):
        return ("Reviewable evidence set", "Variant evidence was summarized; inspect coverage before relying on empty sections.")
    return ("Incomplete evidence set", "Run analysis or load results before interpreting this report.")


def _review_flags(evidence: dict) -> list[tuple[str, str, str]]:
    counts = evidence.get("counts", {})
    mean_depth = _mean_depth_for_evidence(evidence)
    breadth_10 = _mean_breadth_for_evidence(evidence, 10)
    breadth_20 = _mean_breadth_for_evidence(evidence, 20)
    flags: list[tuple[str, str, str]] = []
    if counts.get("variant_rows", 0) and mean_depth and mean_depth < 10:
        flags.append(
            (
                "critical",
                "Low-depth validation data",
                f"Mean depth is {mean_depth:.2f}x with {breadth_10:.2f}% of bases at >=10x. Treat empty or sparse sections as pipeline smoke evidence, not genome interpretation.",
            )
        )
    elif counts.get("variant_rows", 0) and mean_depth >= 20 and breadth_20 >= 80:
        flags.append(("good", "Coverage looks reviewable", f"Mean depth is {mean_depth:.2f}x and >=20x breadth is {breadth_20:.2f}%."))
    elif counts.get("variant_rows", 0):
        flags.append(("warn", "Coverage needs review", "Variants were summarized, but coverage is incomplete or not measured enough for confident interpretation."))
    else:
        flags.append(("warn", "No variant evidence", "This report has no normalized variant rows. Run alignment/calling or load a VCF before interpreting variants."))

    if not evidence.get("files", {}).get("multiqc") and counts.get("qc_reports", 0) == 0:
        flags.append(("warn", "QC package missing", "No FastQC, fastp, or MultiQC report was found for this report."))
    if counts.get("public_annotation_rows", 0) == 0 and counts.get("clinvar_rows", 0) == 0:
        flags.append(("warn", "Public annotation not populated", "ClinVar/dbSNP/gnomAD evidence is absent unless local resources were configured or IDs were already present."))
    if counts.get("consequence_rows", 0) == 0:
        flags.append(("neutral", "No consequence labels", "No VEP CSQ or SnpEff ANN consequence summary was found."))
    return flags


def _review_first_section(evidence: dict) -> str:
    flag_cards = "".join(
        f'<article class="flag {html.escape(level)}"><strong>{html.escape(title)}</strong><p>{html.escape(message)}</p></article>'
        for level, title, message in _review_flags(evidence)
    )
    return f"""
  <h2>Review First</h2>
  <div class="flag-grid">{flag_cards}</div>
  <h3>Variant Mix</h3>
  {_variant_mix_chart(evidence)}
"""


def _resource_state(label: str, configured: str, observed_count: int, ready_note: str, missing_note: str) -> list[object]:
    if configured or observed_count:
        state = "ready" if observed_count else "configured"
        note = ready_note if observed_count else "Configured, but no matching output was found in this report."
    else:
        state = "not configured"
        note = missing_note
    source = configured or ("local output" if observed_count else "")
    return [label, state, observed_count, source, note]


def _genome_overview_section(evidence: dict, args: argparse.Namespace) -> str:
    counts = evidence.get("counts", {})
    readiness, readiness_note = _readiness_state(evidence)
    mean_depth = _mean_depth_for_evidence(evidence)
    breadth_10 = _mean_breadth_for_evidence(evidence, 10)
    breadth_20 = _mean_breadth_for_evidence(evidence, 20)
    breadth_30 = _mean_breadth_for_evidence(evidence, 30)
    multiqc_count = len(evidence.get("files", {}).get("multiqc", []))
    assembly_reports = counts.get("assembly_reports", 0)
    cards = [
        ("Readiness", readiness, readiness_note),
        ("Mean depth", f"{_fmt_number(mean_depth)}x" if mean_depth else "not measured", "Average mosdepth total mean across samples."),
        (">=10x breadth", f"{_fmt_number(breadth_10)}%" if breadth_10 else "not measured", "Broad coverage signal for whether regions were observed."),
        (">=20x breadth", f"{_fmt_number(breadth_20)}%" if breadth_20 else "not measured", "Closer to publication-style WGS quality context."),
        (">=30x breadth", f"{_fmt_number(breadth_30)}%" if breadth_30 else "not measured", "High-depth breadth when available."),
        ("Public evidence", _fmt_number(counts.get("clinvar_rows", 0) + counts.get("public_annotation_rows", 0)), "ClinVar, dbSNP, and gnomAD rows available locally."),
        ("Assembly continuity", _fmt_number(assembly_reports), "gfastats-style continuity reports found."),
        ("QC package", _fmt_number(multiqc_count), "MultiQC reports linked from this run."),
    ]
    card_html = "".join(
        '<div class="overview-card">'
        f"<span>{html.escape(label)}</span>"
        f"<strong>{html.escape(str(value))}</strong>"
        f"<p>{html.escape(note)}</p>"
        "</div>"
        for label, value, note in cards
    )
    resource_rows = [
        _resource_state(
            "Reference",
            args.reference,
            1 if args.reference else 0,
            "Reference FASTA path was recorded for reproducibility.",
            "Set a reference FASTA before running alignment or variant workflows.",
        ),
        _resource_state(
            "ClinVar",
            args.clinvar,
            counts.get("clinvar_rows", 0),
            "ClinVar overlap rows were generated from local resources.",
            "Configure a local ClinVar VCF to populate clinical-annotation evidence.",
        ),
        _resource_state(
            "dbSNP / gnomAD",
            " / ".join(part for part in [args.dbsnp, args.gnomad] if part),
            counts.get("public_annotation_rows", 0),
            "Public ID or population-frequency rows were generated locally.",
            "Configure local dbSNP and gnomAD resources to populate public annotation evidence.",
        ),
        _resource_state(
            "Consequence annotation",
            " / ".join(part for part in [args.vep_cache, args.snpeff_db] if part),
            counts.get("consequence_rows", 0),
            "VEP CSQ or SnpEff ANN consequence rows were summarized.",
            "Use VEP or SnpEff annotations to populate consequence context.",
        ),
        _resource_state(
            "PharmCAT",
            args.pharmcat_jar,
            sum(1 for row in evidence.get("rows", []) for status in row.get("statuses", []) if "pharmcat" in str(status).lower()),
            "PharmCAT status was recorded.",
            "Configure PharmCAT only when PGx reporting is in scope.",
        ),
    ]
    return f"""
  <h2>Genome Overview</h2>
  <p>This overview is designed to read like the first page of a polished sequencing report: publication-style quality context first, then consumer-facing interpretation boundaries.</p>
  <div class="overview-grid">{card_html}</div>
  <div class="interpretation-grid">
    <section>
      <h3>What this report can support</h3>
      <ul>
        <li>Local review of sequencing quality, coverage, variant classes, mtDNA evidence, and public annotation overlaps.</li>
        <li>Reproducible comparison of generated files, configured resources, and optional workflow sections.</li>
        <li>A shareable starting point for expert review without uploading private genome data.</li>
      </ul>
    </section>
    <section>
      <h3>What this report does not claim</h3>
      <ul>
        <li>It does not diagnose disease, assign treatment, or replace clinical review.</li>
        <li>It does not imply that empty sections mean no genetic risk.</li>
        <li>It does not validate ancestry, haplogroup, or pharmacogenomic actionability on its own.</li>
      </ul>
    </section>
  </div>
  <h3>Local Resource Readiness</h3>
  {_html_table(["Resource", "State", "Rows", "Configured source", "Interpretation"], resource_rows, "No resource status was available.")}
"""


def _qc_section(evidence: dict, out_dir: Path) -> str:
    links = []
    for path in evidence["files"].get("multiqc", []):
        links.append(f"<li>{_file_anchor(path, out_dir, 'MultiQC report')}</li>")
    for path in evidence["files"].get("fastp_json", [])[:24]:
        links.append(f"<li>{_file_anchor(path, out_dir)}</li>")
    for path in evidence["files"].get("fastqc", [])[:24]:
        links.append(f"<li>{_file_anchor(path, out_dir)}</li>")
    for path in evidence["files"].get("fastp_html", [])[:24]:
        links.append(f"<li>{_file_anchor(path, out_dir)}</li>")
    if not links:
        return '<p class="empty">No FastQC, fastp, or MultiQC HTML reports were found.</p>'
    return "<ul class=\"file-list\">" + "".join(links) + "</ul>"


def _coverage_section(evidence: dict, out_dir: Path) -> str:
    blocks = []
    density_previews = []
    for path in evidence["files"].get("read_density_plots", []):
        density_previews.append(_image_preview(path, out_dir, "Read density plot"))
    for row in evidence["rows"]:
        coverage_rows = []
        for coverage in row.get("coverage", []):
            total = coverage.get("total", {})
            if total:
                breadth = _breadth_total(row)
                coverage_rows.append(
                    [
                        total.get("chrom", "total"),
                        _safe_int(total.get("length")),
                        _safe_float(total.get("mean")),
                        _safe_float(total.get("min")),
                        _safe_float(total.get("max")),
                        _threshold_pct(breadth, 1),
                        _threshold_pct(breadth, 10),
                        _threshold_pct(breadth, 20),
                        _threshold_pct(breadth, 30),
                    ]
                )
        if not coverage_rows:
            continue
        blocks.append(
            f"<h3>{html.escape(row.get('sample', row.get('row_id', 'sample')))}</h3>"
            + _coverage_chart(row)
            + _html_table(
                ["Region", "Length", "Mean depth", "Min", "Max", ">=1x %", ">=10x %", ">=20x %", ">=30x %"],
                coverage_rows,
                "No coverage rows found.",
            )
        )
    density_html = ""
    if density_previews:
        density_html = '<h3>Read density plots</h3><div class="viz-grid">' + "".join(density_previews[:6]) + "</div>"
    return (density_html + "".join(blocks)) or '<p class="empty">No mosdepth coverage summaries or read density plots were found.</p>'


def _variant_snapshot_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        counts = sample.get("counts", {})
        rows.append(
            [
                sample.get("sample", ""),
                counts.get("variant_rows", 0),
                counts.get("snp_rows", 0),
                counts.get("indel_rows", 0),
                counts.get("mnv_rows", 0),
                counts.get("symbolic_rows", 0),
                counts.get("mitochondrial_variant_rows", 0),
            ]
        )
    return _html_table(
        ["Sample", "Total variants", "SNPs", "Indels", "MNVs", "Symbolic/structural", "Mitochondrial variants"],
        rows,
        "No variant summary rows were found.",
    )


def _mitochondrial_section(evidence: dict, out_dir: Path) -> str:
    rows = []
    status_rows = []
    for sample in evidence["rows"]:
        counts = sample.get("counts", {})
        coverage, breadth = _mito_coverage(sample)
        consensus = sample.get("mitochondria", {}).get("consensus", [])
        consensus_state = "generated" if consensus else "not generated"
        rows.append(
            [
                sample.get("sample", ""),
                coverage.get("chrom", "not found"),
                _safe_float(coverage.get("mean")),
                _threshold_pct(breadth, 1),
                _threshold_pct(breadth, 10),
                counts.get("mitochondrial_variant_rows", 0),
                counts.get("mitochondrial_snp_rows", 0),
                counts.get("mitochondrial_indel_rows", 0),
                consensus_state,
            ]
        )
        for status in sample.get("mitochondria", {}).get("statuses", []):
            status_rows.append(
                [
                    sample.get("sample", status.get("sample", "")),
                    status.get("state", ""),
                    status.get("message", ""),
                ]
            )
    return (
        _html_table(
            [
                "Sample",
                "mtDNA contig",
                "Mean depth",
                ">=1x breadth %",
                ">=10x breadth %",
                "mtDNA variants",
                "mtDNA SNPs",
                "mtDNA indels",
                "Reference-guided consensus",
            ],
            rows,
            "No mitochondrial coverage or variant rows were found.",
        )
        + _html_table(["Sample", "Consensus state", "Message"], status_rows, "No mitochondrial consensus status rows were found.")
    )


def _consequence_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        for item in sample.get("consequences", []):
            rows.append(
                [
                    sample.get("sample", item.get("sample", "")),
                    item.get("tool", ""),
                    item.get("state", ""),
                    item.get("consequence", ""),
                    item.get("impact", ""),
                    item.get("gene", ""),
                    _safe_int(item.get("count")),
                    item.get("note", ""),
                ]
            )
    return _html_table(
        ["Sample", "Tool", "State", "Consequence", "Impact", "Gene", "Count", "Note"],
        rows[:80],
        "No VEP CSQ or SnpEff ANN consequence rows were found.",
    )


def _public_annotation_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        for item in sample.get("public_annotations", []):
            variant = f"{item.get('chrom', '')}:{item.get('pos', '')} {item.get('ref', '')}>{item.get('alt', '')}"
            rows.append(
                [
                    sample.get("sample", item.get("sample", "")),
                    item.get("source", ""),
                    variant,
                    item.get("id", ""),
                    item.get("label", ""),
                    item.get("value", ""),
                    item.get("note", ""),
                ]
            )
    preview_limit = 30
    total = _safe_int(evidence.get("counts", {}).get("public_annotation_rows")) + _safe_int(evidence.get("counts", {}).get("clinvar_rows"))
    summary = (
        f'<p class="table-note">Showing {min(len(rows), preview_limit):,} of {_fmt_number(total)} public annotation rows. '
        "Use <code>findings.tsv</code> and the per-sample TSV outputs for full review.</p>"
        if rows
        else ""
    )
    return summary + _html_table(
        ["Sample", "Source", "Variant", "ID", "Label", "Value", "Note"],
        rows[:preview_limit],
        "No ClinVar, dbSNP, or gnomAD rows were found. Configure local public resources to populate this table.",
    )


def _pgx_section(evidence: dict) -> str:
    rows = []
    for sample in evidence["rows"]:
        for status in sample.get("statuses", []):
            if (status.get("step") or "").lower() in {"pgx", "pharmcat"} or "pharmcat" in status.get("message", "").lower():
                rows.append(
                    [
                        sample.get("sample", status.get("sample", "")),
                        "PharmCAT",
                        status.get("state", ""),
                        status.get("message", ""),
                    ]
                )
    return _html_table(
        ["Sample", "Tool", "State", "Message"],
        rows,
        "No PharmCAT status was found. PGx is not assessed unless PharmCAT is enabled with a local jar.",
    )


def _assembly_section(evidence: dict, out_dir: Path) -> str:
    rows = []
    for sample in evidence["rows"]:
        for assembly in sample.get("assembly", []):
            metrics = assembly.get("metrics", [])
            file_name = Path(str(assembly["file"])).name
            if not metrics:
                rows.append([sample.get("sample", ""), file_name, "report", "generated"])
            for metric in metrics:
                rows.append(
                    [
                        sample.get("sample", ""),
                        file_name,
                        metric.get("metric", ""),
                        metric.get("value", ""),
                    ]
                )
    return _html_table(["Sample", "File", "Metric", "Value"], rows[:80], "No assembly continuity statistics were found.")


def _write_html(path: Path, samples: list[dict[str, str]], evidence: dict, args: argparse.Namespace) -> None:
    counts = evidence.get("counts", {})
    body = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome Report</title>
  <style>
    :root {{
      color-scheme: light;
      --ink: #172026;
      --muted: #5d6a72;
      --line: #d9e0e4;
      --surface: #f6f8f9;
      --accent: #196b69;
      --accent-2: #7a4f12;
      --good: #1f7a4d;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink);
      background: #ffffff;
      line-height: 1.5;
    }}
    main {{ max-width: 1180px; margin: 0 auto; padding: 28px 22px 56px; }}
    header {{ border-bottom: 1px solid var(--line); padding: 34px 0 28px; margin-bottom: 24px; }}
    h1 {{ font-size: clamp(2rem, 3.8vw, 3.6rem); margin: 0 0 10px; line-height: 1.05; letter-spacing: 0; }}
    h2 {{ font-size: 1.35rem; margin: 34px 0 10px; }}
    h3 {{ font-size: 1rem; margin: 24px 0 8px; }}
    p {{ margin: 0 0 12px; }}
    a {{ color: var(--accent); }}
    code {{ background: var(--surface); border: 1px solid var(--line); padding: 0.08rem 0.28rem; border-radius: 4px; }}
    .lede {{ max-width: 820px; color: var(--muted); font-size: 1.05rem; }}
    .generated {{ color: var(--muted); }}
    .boundary {{ border-left: 5px solid var(--accent-2); background: #fff8ed; padding: 14px 16px; margin: 20px 0; }}
    .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; margin: 18px 0 8px; }}
    .metric {{ border: 1px solid var(--line); border-radius: 8px; padding: 14px; background: var(--surface); }}
    .metric strong {{ display: block; font-size: 1.55rem; line-height: 1.1; color: var(--accent); }}
    .metric span {{ color: var(--muted); font-size: 0.88rem; }}
	    .overview-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin: 16px 0 20px; }}
	    .overview-card {{ border: 1px solid var(--line); border-radius: 8px; padding: 14px 15px; background: #fbfcfc; }}
    .overview-card span {{ color: var(--muted); display: block; font-size: 0.82rem; text-transform: uppercase; letter-spacing: 0.04em; }}
    .overview-card strong {{ display: block; color: var(--ink); font-size: 1.18rem; margin: 5px 0 6px; }}
    .overview-card p {{ color: var(--muted); font-size: 0.9rem; margin: 0; }}
    .interpretation-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 14px; margin: 18px 0; }}
	    .interpretation-grid section {{ border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; background: var(--surface); }}
	    .interpretation-grid ul {{ margin: 8px 0 0; padding-left: 1.1rem; }}
	    .flag-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; margin: 14px 0 18px; }}
	    .flag {{ border: 1px solid var(--line); border-left-width: 5px; border-radius: 8px; padding: 14px 16px; background: #fbfcfc; }}
	    .flag strong {{ display: block; margin-bottom: 5px; font-size: 1.02rem; }}
	    .flag p {{ color: var(--muted); margin: 0; }}
	    .flag.critical {{ border-left-color: #b42318; }}
	    .flag.warn {{ border-left-color: #b7791f; }}
	    .flag.good {{ border-left-color: var(--good); }}
	    .flag.neutral {{ border-left-color: #607080; }}
	    .variant-mix {{ display: flex; min-height: 42px; overflow: hidden; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); }}
	    .variant-mix span {{ display: flex; align-items: center; justify-content: center; min-width: 5px; padding: 0 8px; color: white; white-space: nowrap; overflow: hidden; font-size: 0.88rem; }}
	    .variant-mix b {{ margin-right: 4px; }}
	    .variant-mix .snp, .swatch.snp {{ background: #196b69; }}
	    .variant-mix .indel, .swatch.indel {{ background: #7a4f12; }}
	    .variant-mix .mnv, .swatch.mnv {{ background: #4f6673; }}
	    .variant-mix .symbolic, .swatch.symbolic {{ background: #7a3050; }}
	    .legend {{ display: flex; flex-wrap: wrap; gap: 10px 18px; margin: 10px 0 18px; padding: 0; list-style: none; color: var(--muted); }}
	    .swatch {{ display: inline-block; width: 0.75rem; height: 0.75rem; border-radius: 2px; margin-right: 6px; vertical-align: -0.05rem; }}
	    table {{ border-collapse: collapse; width: 100%; margin: 12px 0 18px; font-size: 0.94rem; }}
    th, td {{ border: 1px solid var(--line); padding: 0.48rem 0.55rem; text-align: left; vertical-align: top; }}
    th {{ background: var(--surface); }}
    .file-list {{ columns: 2 280px; padding-left: 1.1rem; }}
	    .empty {{ color: var(--muted); background: var(--surface); border: 1px solid var(--line); padding: 12px; border-radius: 8px; }}
	    .table-note {{ color: var(--muted); margin-top: 0; }}
	    .viz-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 14px; margin: 12px 0 18px; }}
	    .viz-preview {{ margin: 0; border: 1px solid var(--line); border-radius: 8px; background: #fbfcfc; overflow: hidden; }}
	    .viz-preview img {{ display: block; width: 100%; height: auto; }}
	    .viz-preview figcaption {{ padding: 8px 10px; color: var(--muted); border-top: 1px solid var(--line); font-size: 0.9rem; }}
	    .coverage-chart {{ width: 100%; max-height: 320px; border: 1px solid var(--line); border-radius: 8px; background: #fbfcfc; }}
	    .axis {{ stroke: #9aa7ae; stroke-width: 1; }}
	    .target-line {{ stroke: #c6d0d6; stroke-width: 1; stroke-dasharray: 4 4; }}
	    .axis-label, .tick, .target-label {{ fill: #5d6a72; font-size: 12px; text-anchor: middle; }}
	    .axis-label {{ text-anchor: start; }}
	    .target-label {{ text-anchor: start; }}
	    .bar.good {{ fill: var(--good); }}
	    .bar.warn {{ fill: #b7791f; }}
	    .bar.low {{ fill: #b42318; }}
	    .sources {{ color: var(--muted); font-size: 0.92rem; }}
	    @media (max-width: 640px) {{
	      main {{ padding: 18px 14px 42px; }}
	      .variant-mix span {{ justify-content: flex-start; font-size: 0; padding: 0; }}
	      .file-list {{ columns: 1; }}
	      table {{ display: block; overflow-x: auto; }}
	    }}
  </style>
</head>
<body>
<main>
  <header>
    <h1>Open Genome Report</h1>
    <p class="lede">A local, privacy-preserving summary of sequencing quality, coverage, variant evidence, public annotations, and optional pharmacogenomics outputs.</p>
    <p class="generated">Generated {html.escape(evidence['generated_utc'])} from files on this computer.</p>
  </header>

  <section class="boundary">
    <strong>Interpretation boundary:</strong>
    This report is evidence, not diagnosis or treatment advice. Public database matches and computational consequence labels need human review.
  </section>

  <section class="cards" aria-label="Report totals">
    <div class="metric"><strong>{_fmt_number(len(samples) or len(evidence['rows']))}</strong><span>samples</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('variant_rows', 0))}</strong><span>variant rows</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('snp_rows', 0))}</strong><span>SNPs</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('indel_rows', 0))}</strong><span>indels</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('mitochondrial_variant_rows', 0))}</strong><span>mtDNA variants</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('public_annotation_rows', 0))}</strong><span>public annotation rows</span></div>
    <div class="metric"><strong>{_fmt_number(counts.get('consequence_rows', 0))}</strong><span>consequence rows</span></div>
	  </section>

	  {_review_first_section(evidence)}

	  {_genome_overview_section(evidence, args)}

  <h2>Samples</h2>
  {_html_table(["Sample", "Row ID", "Input", "Sex", "QC reports", "Mean depth", ">=10x breadth %", "Variants", "SNPs", "Indels", "mtDNA variants", "ClinVar", "Public annotations", "Consequences", "Status"], _sample_rows(samples, evidence), "No samples were found.")}

  <h2>Quality Reports</h2>
  <p>FastQC, fastp, and MultiQC files are linked here when the pipeline produced them.</p>
  {_qc_section(evidence, path.parent)}

  <h2>Coverage</h2>
  <p>Coverage comes from mosdepth summaries. The chart shows mean depth by reference sequence, and breadth columns show the percent of bases covered at useful thresholds.</p>
  {_coverage_section(evidence, path.parent)}

  <h2>Variant Snapshot</h2>
  <p>These counts separate SNPs, indels, multi-nucleotide variants, and symbolic/structural records so a WGS callset is easier to sanity-check.</p>
  {_variant_snapshot_section(evidence)}

  <h2>Mitochondrial Genome</h2>
  <p>This section summarizes chrM/MT coverage and variants, and links to reference-guided mitochondrial consensus output when the workflow can build it. It is not haplogroup assignment, heteroplasmy validation, or de novo mtDNA assembly.</p>
  {_mitochondrial_section(evidence, path.parent)}

  <h2>Variant Consequences</h2>
  <p>This section summarizes VEP <code>CSQ</code> or SnpEff <code>ANN</code> fields when they are present in the VCF.</p>
  {_consequence_section(evidence)}

  <h2>ClinVar, dbSNP, and gnomAD</h2>
  <p>These rows come only from local public resources or IDs already present in the VCF. Nothing is sent to an external service.</p>
  {_public_annotation_section(evidence)}

  <h2>Pharmacogenomics (PGx)</h2>
  <p>PharmCAT is separated from the rest of the report because PGx findings are medication-context evidence, not general disease-risk findings.</p>
  {_pgx_section(evidence)}

  <h2>Assembly and Continuity</h2>
  <p>N50 and related assembly metrics appear here when an assembly FASTA was supplied.</p>
  {_assembly_section(evidence, path.parent)}

  <h2>Evidence Files</h2>
  <ul class="file-list">
    <li>{_file_anchor(path.parent / 'findings.tsv', path.parent, 'findings.tsv')}</li>
    <li>{_file_anchor(path.parent / 'evidence.json', path.parent, 'evidence.json')}</li>
    <li>{_file_anchor(path.parent / 'run_manifest.json', path.parent, 'run_manifest.json')}</li>
  </ul>
  <p class="sources">Reference: <code>{html.escape(args.reference or '')}</code> · ClinVar: <code>{html.escape(args.clinvar or '')}</code> · dbSNP: <code>{html.escape(args.dbsnp or '')}</code> · gnomAD: <code>{html.escape(args.gnomad or '')}</code> · PharmCAT: <code>{html.escape(args.pharmcat_jar or '')}</code></p>
</main>
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
    parser.add_argument("--gnomad", default="")
    parser.add_argument("--vep-cache", default="")
    parser.add_argument("--snpeff-db", default="")
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
    _write_html(args.out_dir / "report_index.html", samples, evidence, args)
    _write_html(args.out_dir / "open_genome_report.html", samples, evidence, args)
    manifest = {
        "generated_utc": evidence["generated_utc"],
        "samplesheet": str(args.samplesheet),
        "reference": args.reference,
        "clinvar": args.clinvar,
        "dbsnp": args.dbsnp,
        "gnomad": args.gnomad,
        "vep_cache": args.vep_cache,
        "snpeff_db": args.snpeff_db,
        "pharmcat_jar": args.pharmcat_jar,
        "report_index": "report_index.html",
        "legacy_report": "open_genome_report.html",
    }
    _private_write(args.out_dir / "run_manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
