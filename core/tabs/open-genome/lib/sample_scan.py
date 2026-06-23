#!/usr/bin/env python3
"""Scan local genome files and write Open Genome / Sarek samplesheets."""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import tomllib
from pathlib import Path

import manifest_cli


FASTQ_SUFFIXES = (".fastq.gz", ".fq.gz", ".fastq", ".fq")
ASSEMBLY_SUFFIXES = (".fa", ".fasta", ".fna")
LONG_READ_SUFFIXES = FASTQ_SUFFIXES + ASSEMBLY_SUFFIXES + tuple(f"{s}.gz" for s in ASSEMBLY_SUFFIXES) + (".bam",)
OPEN_GENOME_COLUMNS = (
    "sample",
    "row_id",
    "lane",
    "input_type",
    "fastq_1",
    "fastq_2",
    "bam",
    "cram",
    "vcf",
    "assembly",
    "long_reads",
    "sex",
    "status",
)
SAFE_ID_RE = re.compile(r"[^A-Za-z0-9_.-]+")
DENOVO_READ_NAME_RE = re.compile(
    r"(^|[._-])(hifi|ccs|ont|nanopore|ultralong|longread|longreads|long-read|long-reads|pacbio|revio)([._-]|$)",
    flags=re.IGNORECASE,
)


def _safe_id(value: str, default: str = "sample") -> str:
    cleaned = SAFE_ID_RE.sub("_", value.strip())
    cleaned = re.sub(r"_+", "_", cleaned).strip("._-")
    return cleaned or default


def _private_open(path: Path, mode: str):
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(path, flags, 0o600)
    return os.fdopen(fd, mode, encoding="utf-8", newline="")


def _resolve_inside(root: Path, path: Path) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"input path resolves outside selected folder: {path}") from exc
    return resolved


def _strip_fastq_suffix(name: str) -> str:
    for suffix in FASTQ_SUFFIXES:
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def _is_fastq(path: Path) -> bool:
    return path.name.endswith(FASTQ_SUFFIXES)


def _is_assembly(path: Path) -> bool:
    return path.name.endswith(ASSEMBLY_SUFFIXES) or path.name.endswith(tuple(f"{s}.gz" for s in ASSEMBLY_SUFFIXES))


def _is_denovo_read_candidate(path: Path) -> bool:
    return path.name.endswith(LONG_READ_SUFFIXES) and bool(DENOVO_READ_NAME_RE.search(path.name))


def _read_token(name: str) -> str | None:
    if re.search(r"(^|[._-])R1([._-]|$)", name, flags=re.IGNORECASE):
        return "R1"
    if re.search(r"(^|[._-])R2([._-]|$)", name, flags=re.IGNORECASE):
        return "R2"
    if re.search(r"(^|[._-])1([._-]|$)", name):
        return "R1"
    if re.search(r"(^|[._-])2([._-]|$)", name):
        return "R2"
    return None


def _pair_key(path: Path) -> tuple[str, str]:
    stem = _strip_fastq_suffix(path.name)
    lane_match = re.search(r"(^|[._-])(L\d{3})([._-]|$)", stem, flags=re.IGNORECASE)
    lane = lane_match.group(2) if lane_match else "lane_1"
    sample = re.sub(r"(^|[._-])R[12]([._-]|$)", r"\1", stem, flags=re.IGNORECASE)
    sample = re.sub(r"(^|[._-])[12]([._-]|$)", r"\1", sample)
    sample = re.sub(r"(^|[._-])L\d{3}([._-]|$)", r"\1", sample, flags=re.IGNORECASE)
    sample = re.sub(r"[._-]+$", "", re.sub(r"^[._-]+", "", sample))
    sample = _safe_id(sample)
    return sample, lane


def _find_fastq_rows(root: Path) -> tuple[list[dict[str, str]], list[str]]:
    grouped: dict[tuple[str, str], dict[str, Path]] = {}
    warnings: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not _is_fastq(path):
            continue
        token = _read_token(path.name)
        if token is None:
            if _is_denovo_read_candidate(path):
                continue
            warnings.append(f"unpaired/unknown FASTQ read token: {path}")
            continue
        try:
            resolved = _resolve_inside(root, path)
        except ValueError as exc:
            warnings.append(str(exc))
            continue
        sample, lane = _pair_key(resolved)
        grouped.setdefault((sample, lane), {})[token] = resolved

    rows: list[dict[str, str]] = []
    for (sample, lane), reads in sorted(grouped.items()):
        if "R1" not in reads or "R2" not in reads:
            warnings.append(f"missing mate for sample={sample} lane={lane}")
            continue
        rows.append(
            {
                "sample": sample,
                "row_id": _safe_id(f"{sample}_{lane}"),
                "lane": lane,
                "input_type": "fastq",
                "fastq_1": str(reads["R1"].resolve()),
                "fastq_2": str(reads["R2"].resolve()),
                "bam": "",
                "cram": "",
                "vcf": "",
                "assembly": "",
                "long_reads": "",
                "sex": "NA",
                "status": "0",
                "_lane": lane,
            }
        )
    return rows, warnings


def _find_alignment_rows(root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if _is_denovo_read_candidate(path):
            continue
        resolved = _resolve_inside(root, path)
        sample = _safe_id(path.stem)
        if path.suffix == ".bam":
            rows.append(
                {
                    "sample": sample,
                    "row_id": _safe_id(f"{sample}_bam"),
                    "lane": "lane_1",
                    "input_type": "alignment",
                    "fastq_1": "",
                    "fastq_2": "",
                    "bam": str(resolved),
                    "cram": "",
                    "vcf": "",
                    "assembly": "",
                    "long_reads": "",
                    "sex": "NA",
                    "status": "0",
                    "_lane": "lane_1",
                }
            )
        elif path.suffix == ".cram":
            rows.append(
                {
                    "sample": sample,
                    "row_id": _safe_id(f"{sample}_cram"),
                    "lane": "lane_1",
                    "input_type": "alignment",
                    "fastq_1": "",
                    "fastq_2": "",
                    "bam": "",
                    "cram": str(resolved),
                    "vcf": "",
                    "assembly": "",
                    "long_reads": "",
                    "sex": "NA",
                    "status": "0",
                    "_lane": "lane_1",
                }
            )
    return rows


def _find_vcf_rows(root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.name.endswith(".vcf") or path.name.endswith(".vcf.gz"):
            resolved = _resolve_inside(root, path)
            sample = _safe_id(path.name.removesuffix(".vcf.gz").removesuffix(".vcf"))
            rows.append(
                {
                    "sample": sample,
                    "row_id": _safe_id(f"{sample}_vcf"),
                    "lane": "lane_1",
                    "input_type": "vcf",
                    "fastq_1": "",
                    "fastq_2": "",
                    "bam": "",
                    "cram": "",
                    "vcf": str(resolved),
                    "assembly": "",
                    "long_reads": "",
                    "sex": "NA",
                    "status": "0",
                    "_lane": "lane_1",
                }
            )
    return rows


def _find_long_read_rows(root: Path, fastq_rows: list[dict[str, str]] | None = None) -> list[dict[str, str]]:
    used_fastqs = set()
    for row in fastq_rows or []:
        for key in ("fastq_1", "fastq_2"):
            if row.get(key):
                used_fastqs.add(Path(row[key]).resolve())

    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not _is_denovo_read_candidate(path):
            continue
        resolved = _resolve_inside(root, path)
        if resolved in used_fastqs:
            continue
        sample = path.name
        for suffix in (
            ".fastq.gz",
            ".fq.gz",
            ".fasta.gz",
            ".fna.gz",
            ".fa.gz",
            ".fastq",
            ".fq",
            ".fasta",
            ".fna",
            ".fa",
            ".bam",
        ):
            sample = sample.removesuffix(suffix)
        sample = _safe_id(sample)
        rows.append(
            {
                "sample": sample,
                "row_id": _safe_id(f"{sample}_long_reads"),
                "lane": "lane_1",
                "input_type": "long_reads",
                "fastq_1": "",
                "fastq_2": "",
                "bam": "",
                "cram": "",
                "vcf": "",
                "assembly": "",
                "long_reads": str(resolved),
                "sex": "NA",
                "status": "0",
                "_lane": "lane_1",
            }
        )
    return rows


def _find_assembly_rows(root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not _is_assembly(path):
            continue
        if _is_denovo_read_candidate(path):
            continue
        resolved = _resolve_inside(root, path)
        sample = path.name
        for suffix in (".fasta.gz", ".fastq.gz", ".fna.gz", ".fa.gz", ".fasta", ".fastq", ".fna", ".fa"):
            sample = sample.removesuffix(suffix)
        sample = _safe_id(sample)
        rows.append(
            {
                "sample": sample,
                "row_id": _safe_id(f"{sample}_assembly"),
                "lane": "lane_1",
                "input_type": "assembly",
                "fastq_1": "",
                "fastq_2": "",
                "bam": "",
                "cram": "",
                "vcf": "",
                "assembly": str(resolved),
                "long_reads": "",
                "sex": "NA",
                "status": "0",
                "_lane": "lane_1",
            }
        )
    return rows


def _sarek_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    converted: list[dict[str, str]] = []
    for row in rows:
        input_type = row.get("input_type", "")
        base = {
            "patient": row.get("sample", "sample"),
            "sex": row.get("sex", "NA") or "NA",
            "status": row.get("status", "0") or "0",
            "sample": row.get("sample", "sample"),
            "lane": row.get("lane") or row.get("_lane", "lane_1") or "lane_1",
        }
        if input_type == "fastq":
            converted.append({**base, "fastq_1": row["fastq_1"], "fastq_2": row["fastq_2"]})
        elif input_type == "alignment" and row.get("bam"):
            converted.append({**base, "bam": row["bam"]})
        elif input_type == "alignment" and row.get("cram"):
            converted.append({**base, "cram": row["cram"]})
        elif input_type == "vcf":
            converted.append({"patient": base["patient"], "sample": base["sample"], "vcf": row["vcf"]})
    return converted


def _recommended_plan(rows: list[dict[str, str]]) -> str:
    counts: dict[str, int] = {}
    long_read_paths: list[str] = []
    for row in rows:
        input_type = row.get("input_type", "").strip()
        if not input_type:
            continue
        counts[input_type] = counts.get(input_type, 0) + 1
        if input_type == "long_reads":
            long_read_paths.append(row.get("long_reads", "").lower())

    if not counts:
        return "No runnable inputs detected"
    if set(counts) == {"fastq"}:
        return "Illumina WGS -> BWA-MEM2 + GATK"
    if set(counts) == {"alignment"}:
        return "BAM/CRAM -> reference workflow, caller chosen at run preparation"
    if set(counts) == {"vcf"}:
        return "Existing VCF -> report-only workflow"
    if set(counts) == {"assembly"}:
        return "Assembly FASTA -> existing assembly/report review"
    if set(counts) == {"long_reads"}:
        joined = " ".join(long_read_paths)
        if any(token in joined for token in ("ont", "nanopore", "ultralong")):
            return "ONT long reads -> minimap2 + Clair3; de novo uses Flye"
        return "PacBio HiFi/CCS -> pbmm2 + Clair3; de novo uses hifiasm"
    detail = ", ".join(f"{key}={value}" for key, value in sorted(counts.items()))
    return f"Mixed inputs ({detail}) -> run preparation will ask for one outcome"


def _write_samplesheet(path: Path, rows: list[dict[str, str]], columns: tuple[str, ...] | None = None) -> None:
    if not rows:
        raise ValueError("no sample rows to write")
    fieldnames = list(columns or tuple(k for k in rows[0].keys() if not k.startswith("_")))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    with _private_open(path, "w") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def _load_manifest() -> dict:
    user = manifest_cli._user_manifest()
    if not user.is_file():
        return {}
    return tomllib.loads(user.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--schema", choices=("opengenome", "sarek"), default="opengenome")
    parser.add_argument("--sarek-out", type=Path, default=None, help="Optional Sarek-compatible CSV to write too")
    args = parser.parse_args(argv)

    root = args.input_dir.expanduser().resolve()
    if not root.is_dir():
        print(f"Input is not a directory: {root}", file=sys.stderr)
        return 1

    data = _load_manifest()
    workdir = str(data.get("paths", {}).get("workdir", "") or "")
    if not workdir:
        workdir = str((Path.home() / ".local" / "share" / "open-genome" / "work").resolve())
    default_name = "open_genome_samplesheet.csv" if args.schema == "opengenome" else "sarek_samplesheet.csv"
    out = args.out or Path(workdir) / "samples" / default_name

    fastq_rows, warnings = _find_fastq_rows(root)
    long_read_rows = _find_long_read_rows(root, fastq_rows)
    align_rows = _find_alignment_rows(root)
    vcf_rows = _find_vcf_rows(root)
    assembly_rows = _find_assembly_rows(root)
    rows = fastq_rows + long_read_rows + align_rows + vcf_rows + assembly_rows
    modes = [
        name
        for name, found in (
            ("fastq", fastq_rows),
            ("long_reads", long_read_rows),
            ("alignment", align_rows),
            ("vcf", vcf_rows),
            ("assembly", assembly_rows),
        )
        if found
    ]
    mode = modes[0] if len(modes) == 1 else "mixed"

    if not rows:
        print(f"No paired FASTQ, long-read, BAM/CRAM, VCF, or assembly inputs found under {root}", file=sys.stderr)
        for warning in warnings:
            print(f"warning: {warning}", file=sys.stderr)
        return 1

    if args.schema == "sarek":
        output_rows = _sarek_rows(rows)
        _write_samplesheet(out, output_rows)
    else:
        output_rows = rows
        _write_samplesheet(out, output_rows, OPEN_GENOME_COLUMNS)
    sarek_out = args.sarek_out
    if sarek_out:
        sarek_rows = _sarek_rows(rows)
        if sarek_rows:
            _write_samplesheet(sarek_out, sarek_rows)
    first = rows[0]
    recommended_plan = _recommended_plan(rows)
    user = manifest_cli._user_manifest()
    data.setdefault("paths", {})["dataset"] = str(root)
    sample = data.setdefault("sample", {})
    sample["input_dir"] = str(root)
    sample["sample_id"] = first.get("sample", "")
    sample["patient_id"] = first.get("sample", "")
    sample["input_type"] = mode
    sample["sex"] = first.get("sex", "NA")
    sample["status"] = first.get("status", "0")
    sample["samplesheet"] = str(out.resolve())
    sample["recommended_plan"] = recommended_plan
    if sarek_out:
        sample["sarek_samplesheet"] = str(sarek_out.resolve())
    manifest_cli._write_manifest(user, data)

    print(f"Detected input mode: {mode}")
    print(f"Rows written: {len(rows)}")
    print("Input type counts:")
    for name, found in (
        ("fastq", fastq_rows),
        ("long_reads", long_read_rows),
        ("alignment", align_rows),
        ("vcf", vcf_rows),
        ("assembly", assembly_rows),
    ):
        print(f"  {name}: {len(found)}")
    print(f"Recommended plan: {recommended_plan}")
    print("Sample rows:")
    for row in rows[:10]:
        print(f"  {row.get('row_id', row.get('sample', 'sample'))}: {row['input_type']} ({row['sample']})")
    print(f"Samplesheet: {out.resolve()}")
    if sarek_out:
        print(f"Sarek samplesheet: {sarek_out.resolve()}")
    for warning in warnings:
        print(f"warning: {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
