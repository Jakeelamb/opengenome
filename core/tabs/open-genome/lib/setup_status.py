#!/usr/bin/env python3
"""Read-only Open Genome setup readiness evaluation."""
from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import manifest_cli


DEFAULT_MANIFEST = Path(__file__).resolve().parent.parent / "manifest.default.toml"


def _load_or_default() -> tuple[Path, dict]:
    user = manifest_cli._user_manifest()
    if user.is_file():
        return user, manifest_cli._load(user)
    return user, manifest_cli._load(DEFAULT_MANIFEST)


def _value(data: dict, section: str, key: str) -> str:
    value = data.get(section, {}).get(key, "")
    return "" if value is None else str(value)


def _is_true(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _path_exists(path: str, kind: str) -> bool:
    if not path:
        return False
    p = Path(path).expanduser()
    if kind == "file":
        return p.is_file()
    if kind == "dir":
        return p.is_dir()
    return p.exists()


def _clair3_model_ready(path: str) -> bool:
    if not path:
        return False
    root = Path(path).expanduser()
    return (root / "pileup.pt").is_file() and (root / "full_alignment.pt").is_file()


def _recommended_plan(samplesheet: str, sample_type: str) -> str:
    if not samplesheet or not Path(samplesheet).is_file():
        if sample_type:
            return f"{sample_type}: choose sequencing files again if this looks wrong"
        return "choose sequencing files to pick a recommended path"

    counts: dict[str, int] = {}
    long_read_paths: list[str] = []
    try:
        with Path(samplesheet).open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                input_type = (row.get("input_type") or "").strip()
                if not input_type:
                    continue
                counts[input_type] = counts.get(input_type, 0) + 1
                if input_type == "long_reads":
                    long_read_paths.append((row.get("long_reads") or "").lower())
    except OSError:
        return "samplesheet is unreadable; choose sequencing files again"

    if not counts and sample_type == "fastq":
        return "Illumina WGS -> BWA-MEM2 + GATK"
    if not counts and sample_type == "long_reads":
        return "Long reads -> Clair3 reference workflow; de novo assembly available"
    if not counts and sample_type == "alignment":
        return "BAM/CRAM -> reference workflow, caller chosen at run preparation"
    if not counts and sample_type == "vcf":
        return "Existing VCF -> report-only workflow"
    if not counts and sample_type == "assembly":
        return "Assembly FASTA -> existing assembly/report review"
    if not counts:
        return "samplesheet has no runnable rows"
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


def _run(command: list[str]) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(command, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None


def resolve_conda(data: dict) -> dict:
    override = _value(data, "conda", "conda_exe")
    if override:
        p = Path(override).expanduser()
        if p.is_file() and os.access(p, os.X_OK):
            return {"state": "ok", "path": str(p), "source": "manifest"}
    conda = shutil.which("conda")
    if conda:
        return {"state": "ok", "path": conda, "source": "PATH"}
    mamba = shutil.which("mamba")
    if mamba:
        return {"state": "ok", "path": mamba, "source": "PATH"}
    if override:
        return {"state": "missing", "path": "", "source": "manifest", "message": f"Configured conda is not executable: {override}"}
    return {"state": "missing", "path": "", "source": "", "message": "No conda executable found"}


def env_exists(conda: dict, env_name: str) -> bool:
    exe = conda.get("path", "")
    if not exe:
        return False
    result = _run([exe, "env", "list"])
    if result is None or result.returncode != 0:
        return False
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields and fields[0] == env_name:
            return True
    return False


def item(label: str, ok: bool, detail: str, next_action: str = "") -> dict:
    return {"label": label, "ok": ok, "detail": detail if ok else next_action, "value": detail, "next": next_action}


def info(label: str, detail: str) -> dict:
    return {"label": label, "ok": None, "detail": detail, "value": detail, "next": ""}


def evaluate() -> dict:
    manifest_path, data = _load_or_default()
    conda = resolve_conda(data)
    conda_detail = conda.get("path") or conda.get("message", "")

    workdir = _value(data, "paths", "workdir")
    dataset = _value(data, "paths", "dataset")
    samplesheet = _value(data, "sample", "samplesheet")
    sample_type = _value(data, "sample", "input_type")
    analysis_plan = _value(data, "sample", "recommended_plan") or _recommended_plan(samplesheet, sample_type)
    reference_path = _value(data, "paths", "reference")
    fasta = _value(data, "reference", "fasta")
    fai = _value(data, "reference", "fai")
    dict_path = _value(data, "reference", "dict")
    dbsnp = _value(data, "reference", "dbsnp")
    bwa_ready = data.get("reference", {}).get("bwa_index_ready", False)
    bwa_mem2_ready = data.get("reference", {}).get("bwa_mem2_index_ready", False)
    clinvar = _value(data, "cache", "clinvar_vcf")
    clinvar_tbi = _value(data, "cache", "clinvar_tbi")
    gnomad = _value(data, "cache", "gnomad_vcf")
    vep_cache = _value(data, "cache", "vep_cache")
    snpeff_db = _value(data, "cache", "snpeff_db")
    pharmcat_jar = _value(data, "cache", "pharmcat_jar")
    clair3_hifi_model = _value(data, "cache", "clair3_hifi_model")
    clair3_ont_model = _value(data, "cache", "clair3_ont_model")
    outdir = _value(data, "workflow", "outdir")
    params_file = _value(data, "workflow", "params_file")
    command_file = _value(data, "workflow", "command_file")
    denovo_outdir = _value(data, "workflow", "denovo_outdir")
    denovo_command_file = _value(data, "workflow", "denovo_command_file")
    report_html = _value(data, "results", "report_html")
    findings_tsv = _value(data, "results", "findings_tsv")
    evidence_json = _value(data, "results", "evidence_json")
    denovo_report_html = _value(data, "results", "denovo_report_html")
    threads = _value(data, "paths", "threads")

    sections = [
        {
            "name": "Machine",
            "items": [
                item("Conda available", conda["state"] == "ok", conda_detail, "Start Here -> Advanced manual setup -> Use existing conda or Install private conda"),
                item("Open Genome tools", env_exists(conda, "opengenome"), "opengenome", "Start Here -> Advanced manual setup -> Install or update local tools"),
                item("De novo assembly tools", env_exists(conda, "opengenome-denovo"), "opengenome-denovo", "Start Here -> Advanced manual setup -> Install or update local tools"),
                item("Output folder", _path_exists(workdir, "dir"), workdir, "Start Here -> Advanced manual setup -> Choose results folder"),
                info("CPU usage limit", threads or "optional; defaults to available CPUs"),
            ],
        },
        {
            "name": "Input data",
            "items": [
                item("Sequencing folder", _path_exists(dataset, "dir"), dataset, "Start Here -> Start guided setup or Advanced manual setup -> Choose sequencing files"),
                item("Samplesheet", _path_exists(samplesheet, "file"), samplesheet, "Start Here -> Start guided setup or Advanced manual setup -> Choose sequencing files"),
                item("Detected input type", bool(sample_type), sample_type, "Start Here -> Start guided setup or Advanced manual setup -> Choose sequencing files"),
                info("Recommended plan", analysis_plan),
            ],
        },
        {
            "name": "Reference",
            "items": [
                item("Chosen reference path", _path_exists(reference_path, "either"), reference_path, "Start Here -> Advanced manual setup -> Choose reference genome"),
                item("Reference FASTA", _path_exists(fasta, "file"), fasta, "Start Here -> Advanced manual setup -> Download reference genome"),
                item("Reference FAI", _path_exists(fai, "file"), fai, "Run Analysis -> Advanced workflow steps -> Index reference genome"),
                item("Reference dict", _path_exists(dict_path, "file"), dict_path, "Run Analysis -> Advanced workflow steps -> Index reference genome"),
                item("BWA index", _is_true(bwa_ready), "ready", "Run Analysis -> Advanced workflow steps -> Index reference genome"),
                item("BWA-MEM2 index", _is_true(bwa_mem2_ready), "ready", "Run Analysis -> Advanced workflow steps -> Index reference genome"),
                item("dbSNP VCF", _path_exists(dbsnp, "file"), dbsnp, "Start Here -> Advanced manual setup -> Download reference genome"),
            ],
        },
        {
            "name": "Local models and report evidence",
            "items": [
                item("Clair3 HiFi model", _clair3_model_ready(clair3_hifi_model), clair3_hifi_model, "Start Here -> Advanced manual setup -> Download Clair3 models"),
                item("Clair3 ONT model", _clair3_model_ready(clair3_ont_model), clair3_ont_model, "Start Here -> Advanced manual setup -> Download Clair3 models"),
                info("ClinVar VCF", clinvar or "not configured"),
                info("gnomAD VCF", gnomad or "not configured"),
                info("VEP cache", vep_cache or "not configured"),
                info("SnpEff database", snpeff_db or "not configured"),
                info("PharmCAT jar", pharmcat_jar or "not configured"),
            ],
        },
        {
            "name": "Workflow",
            "items": [
                item("Workflow output folder", _path_exists(outdir, "dir"), outdir, "Run Analysis -> Run reference-based analysis or Run existing VCF report"),
                item("Params file", _path_exists(params_file, "file"), params_file, "Run Analysis -> Run reference-based analysis or Run existing VCF report"),
                item("Run command", _path_exists(command_file, "file"), command_file, "Run Analysis -> Run reference-based analysis or Run existing VCF report"),
                info("De novo output folder", denovo_outdir or "not prepared"),
                info("De novo run command", denovo_command_file or "not prepared"),
            ],
        },
        {
            "name": "Results",
            "items": [
                item("HTML report", _path_exists(report_html, "file"), report_html, "Start Here -> Load existing results or Run Analysis -> Run reference-based analysis"),
                item("Findings table", _path_exists(findings_tsv, "file"), findings_tsv, "Start Here -> Load existing results or Run Analysis -> Run reference-based analysis"),
                item("Evidence JSON", _path_exists(evidence_json, "file"), evidence_json, "Start Here -> Load existing results or Run Analysis -> Run reference-based analysis"),
                info("De novo HTML report", denovo_report_html or "not run"),
            ],
        },
    ]
    checks = [entry for section in sections for entry in section["items"] if entry["ok"] is not None]
    ready = sum(1 for entry in checks if entry["ok"])
    saved = {
        "Work folder": workdir or "not set",
        "Sequencing folder": dataset or "not set",
        "Samplesheet": samplesheet or "not set",
        "Reference": fasta or reference_path or "not set",
        "Workflow output": outdir or "not set",
        "De novo output": denovo_outdir or "not set",
        "Report": report_html or "not set",
    }
    return {
        "manifest": str(manifest_path),
        "sections": sections,
        "ready": ready,
        "total": len(checks),
        "status": "ready to review results" if ready == len(checks) else "run the listed setup actions for unchecked items",
        "saved_locations": saved,
        "recommended_plan": analysis_plan,
    }


def print_text(status: dict) -> None:
    print("Open Genome setup checklist")
    print("")
    for section in status["sections"]:
        print(section["name"])
        for entry in section["items"]:
            if entry["ok"] is True:
                marker = "[x]"
            elif entry["ok"] is False:
                marker = "[ ]"
            else:
                marker = "[-]"
            print(f"{marker} {entry['label']:<28} {entry['detail']}")
        print("")
    print(f"Ready: {status['ready']}/{status['total']} checks complete")
    print(f"Status: {status['status']}.")
    print("")
    print("Saved locations")
    for label, value in status["saved_locations"].items():
        print(f"  {label + ':':<18} {value}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    args = parser.parse_args(argv)
    status = evaluate()
    if args.json:
        print(json.dumps(status, indent=2, sort_keys=True))
    else:
        print_text(status)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
