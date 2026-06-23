#!/usr/bin/env python3
"""Read/write the Open Genome manifest (tomllib read + schema-aware write)."""
from __future__ import annotations

import os
import shutil
import sys
import tomllib
from pathlib import Path


def _user_manifest() -> Path:
    if override := os.environ.get("OPEN_GENOME_CONFIG_DIR"):
        return Path(override) / "manifest.toml"
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "open-genome" / "manifest.toml"


def _escape_toml_basic(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def _load(path: Path) -> dict:
    return tomllib.loads(path.read_text(encoding="utf-8"))


def _bool(value: object, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _write_str_section(lines: list[str], title: str, values: dict, keys: tuple[str, ...]) -> None:
    lines.append(f"[{title}]")
    for key in keys:
        lines.append(f'{key} = "{_escape_toml_basic(str(values.get(key, "") or ""))}"')
    lines.append("")


def _write_manifest(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    lines: list[str] = []
    lines.append("# Open Genome - local paths, sample metadata, workflow state, and enabled module ids.")
    lines.append("")
    paths = data.setdefault("paths", {})
    _write_str_section(lines, "paths", paths, ("reference", "dataset", "workdir", "threads"))

    conda = data.setdefault("conda", {})
    lines.append("[conda]")
    lines.append(f"prefer_mamba = {str(bool(conda.get('prefer_mamba', False))).lower()}")
    lines.append(f'install_root = "{_escape_toml_basic(str(conda.get("install_root", "") or ""))}"')
    if conda.get("conda_exe"):
        lines.append(f'conda_exe = "{_escape_toml_basic(str(conda["conda_exe"]))}"')
    lines.append("")

    privacy = data.setdefault("privacy", {})
    lines.append("[privacy]")
    lines.append(f"local_only = {str(_bool(privacy.get('local_only'), True)).lower()}")
    lines.append("")

    sample = data.setdefault("sample", {})
    _write_str_section(
        lines,
        "sample",
        sample,
        (
            "input_dir",
            "sample_id",
            "patient_id",
            "input_type",
            "sex",
            "status",
            "samplesheet",
            "sarek_samplesheet",
            "recommended_plan",
        ),
    )

    reference = data.setdefault("reference", {})
    lines.append("[reference]")
    for k in (
        "profile",
        "bundle_dir",
        "fasta",
        "fai",
        "dict",
        "dbsnp",
        "known_indels",
        "mills_indels",
        "thousand_genomes_snps",
    ):
        default = "gatk_grch38" if k == "profile" else ""
        lines.append(f'{k} = "{_escape_toml_basic(str(reference.get(k, default) or ""))}"')
    lines.append(f"bwa_index_ready = {str(_bool(reference.get('bwa_index_ready'), False)).lower()}")
    lines.append("")

    workflow = data.setdefault("workflow", {})
    for key, default in (
        ("engine", "opengenome"),
        ("pipeline_version", "v1"),
        ("sarek_version", "3.8.1"),
        ("runtime", "conda"),
    ):
        workflow.setdefault(key, default)
    _write_str_section(
        lines,
        "workflow",
        workflow,
        (
            "engine",
            "pipeline_version",
            "sarek_version",
            "runtime",
            "native_profile",
            "sarek_runtime",
            "outdir",
            "params_file",
            "command_file",
            "recommended_plan",
            "last_run_dir",
            "denovo_outdir",
            "denovo_params_file",
            "denovo_command_file",
            "denovo_last_run_dir",
        ),
    )

    results = data.setdefault("results", {})
    _write_str_section(
        lines,
        "results",
        results,
        (
            "summary_file",
            "multiqc_dir",
            "variant_stats_file",
            "report_dir",
            "report_html",
            "findings_tsv",
            "evidence_json",
            "denovo_report_dir",
            "denovo_report_html",
            "denovo_summary_tsv",
            "denovo_manifest_json",
        ),
    )

    cache = data.setdefault("cache", {})
    _write_str_section(
        lines,
        "cache",
        cache,
        (
            "root",
            "release_manifest",
            "clinvar_vcf",
            "clinvar_tbi",
            "dbsnp_vcf",
            "dbsnp_tbi",
            "gnomad_vcf",
            "gnomad_tbi",
            "vep_cache",
            "snpeff_db",
            "snpeff_config",
            "pharmcat_jar",
            "clair3_hifi_model",
            "clair3_ont_model",
        ),
    )

    for m in data.get("modules", []):
        lines.append("[[modules]]")
        lines.append(f'id = "{_escape_toml_basic(str(m.get("id", "")))}"')
        lines.append(f"enabled = {str(bool(m.get('enabled', True))).lower()}")
        lines.append("")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")


def _deep_set(data: dict, dotted: str, value: str) -> None:
    parts = dotted.split(".")
    cur: dict = data
    for p in parts[:-1]:
        cur = cur.setdefault(p, {})
    old = cur.get(parts[-1])
    if isinstance(old, bool):
        cur[parts[-1]] = _bool(value, old)
    else:
        cur[parts[-1]] = value


def _deep_get(data: dict, dotted: str) -> str:
    cur: object = data
    for p in dotted.split("."):
        if not isinstance(cur, dict) or p not in cur:
            return ""
        cur = cur[p]
    return "" if cur is None else str(cur)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: manifest_cli.py init <default.toml>|show|get <key>|set <key> <value>", file=sys.stderr)
        return 2

    cmd = argv[1]
    user = _user_manifest()

    if cmd == "init":
        if len(argv) < 3:
            print("init requires path to manifest.default.toml", file=sys.stderr)
            return 2
        default_path = Path(argv[2])
        user.parent.mkdir(parents=True, exist_ok=True)
        user.parent.chmod(0o700)
        if not user.exists():
            shutil.copy(default_path, user)
            user.chmod(0o600)
            print(f"Wrote {user}")
        else:
            print(f"Exists: {user} (unchanged)")
        return 0

    if cmd == "bootstrap":
        # init if missing, then merge paths from legacy paths.env only when manifest paths are empty
        if len(argv) < 3:
            print("bootstrap requires path to manifest.default.toml", file=sys.stderr)
            return 2
        default_path = Path(argv[2])
        user.parent.mkdir(parents=True, exist_ok=True)
        user.parent.chmod(0o700)
        if not user.exists():
            shutil.copy(default_path, user)
            user.chmod(0o600)
            print(f"Wrote {user}")
        legacy = user.parent / "paths.env"
        if legacy.is_file():
            data = _load(user)
            paths = data.setdefault("paths", {})
            manifest_empty = not any(str(paths.get(k, "") or "").strip() for k in ("reference", "dataset", "workdir", "threads"))
            if not manifest_empty:
                return 0
            changed = False
            for line in legacy.read_text(encoding="utf-8").splitlines():
                if "=" not in line or line.strip().startswith("#"):
                    continue
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip()
                if k == "OPEN_GENOME_REFERENCE" and v:
                    paths["reference"] = v
                    changed = True
                elif k == "OPEN_GENOME_DATASET" and v:
                    paths["dataset"] = v
                    changed = True
                elif k == "OPEN_GENOME_WORKDIR" and v:
                    paths["workdir"] = v
                    changed = True
                elif k == "OPEN_GENOME_THREADS" and v:
                    paths["threads"] = v
                    changed = True
            if changed:
                _write_manifest(user, data)
                print("Imported paths from paths.env into manifest.toml")
        return 0

    if not user.is_file():
        print(f"Missing {user}; run init or bootstrap first.", file=sys.stderr)
        return 1

    data = _load(user)

    if cmd == "show":
        print(f"manifest: {user}")
        paths = data.get("paths", {})
        for k in ("reference", "dataset", "workdir", "threads"):
            print(f"  paths.{k}={paths.get(k, '')!r}")
        conda = data.get("conda", {})
        print(f"  conda.prefer_mamba={conda.get('prefer_mamba', False)}")
        if conda.get("install_root"):
            print(f"  conda.install_root={conda['install_root']!r}")
        if conda.get("conda_exe"):
            print(f"  conda.conda_exe={conda['conda_exe']!r}")
        privacy = data.get("privacy", {})
        print(f"  privacy.local_only={privacy.get('local_only', True)}")
        sample = data.get("sample", {})
        for k in (
            "input_dir",
            "sample_id",
            "patient_id",
            "input_type",
            "sex",
            "status",
            "samplesheet",
            "sarek_samplesheet",
            "recommended_plan",
        ):
            print(f"  sample.{k}={sample.get(k, '')!r}")
        reference = data.get("reference", {})
        for k in (
            "profile",
            "bundle_dir",
            "fasta",
            "fai",
            "dict",
            "bwa_index_ready",
            "dbsnp",
            "known_indels",
            "mills_indels",
            "thousand_genomes_snps",
        ):
            print(f"  reference.{k}={reference.get(k, '')!r}")
        workflow = data.get("workflow", {})
        for k in (
            "engine",
            "pipeline_version",
            "sarek_version",
            "runtime",
            "native_profile",
            "sarek_runtime",
            "outdir",
            "params_file",
            "command_file",
            "recommended_plan",
            "last_run_dir",
            "denovo_outdir",
            "denovo_params_file",
            "denovo_command_file",
            "denovo_last_run_dir",
        ):
            print(f"  workflow.{k}={workflow.get(k, '')!r}")
        results = data.get("results", {})
        for k in (
            "summary_file",
            "multiqc_dir",
            "variant_stats_file",
            "report_dir",
            "report_html",
            "findings_tsv",
            "evidence_json",
            "denovo_report_dir",
            "denovo_report_html",
            "denovo_summary_tsv",
            "denovo_manifest_json",
        ):
            print(f"  results.{k}={results.get(k, '')!r}")
        cache = data.get("cache", {})
        for k in (
            "root",
            "release_manifest",
            "clinvar_vcf",
            "clinvar_tbi",
            "dbsnp_vcf",
            "dbsnp_tbi",
            "gnomad_vcf",
            "gnomad_tbi",
            "vep_cache",
            "snpeff_db",
            "snpeff_config",
            "pharmcat_jar",
        ):
            print(f"  cache.{k}={cache.get(k, '')!r}")
        for m in data.get("modules", []):
            print(f"  module {m.get('id')} enabled={m.get('enabled', True)}")
        return 0

    if cmd == "get" and len(argv) >= 3:
        print(_deep_get(data, argv[2]))
        return 0

    if cmd == "set" and len(argv) >= 4:
        _deep_set(data, argv[2], argv[3])
        _write_manifest(user, data)
        return 0

    print("unknown command", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
