#!/usr/bin/env python3
from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import manifest_cli
import setup_status


class SetupStatusTests(unittest.TestCase):
    def test_missing_manifest_is_read_only_and_reports_missing(self) -> None:
        with tempfile.TemporaryDirectory() as cfg:
            old_cfg = os.environ.get("OPEN_GENOME_CONFIG_DIR")
            os.environ["OPEN_GENOME_CONFIG_DIR"] = cfg
            try:
                status = setup_status.evaluate()
            finally:
                if old_cfg is None:
                    os.environ.pop("OPEN_GENOME_CONFIG_DIR", None)
                else:
                    os.environ["OPEN_GENOME_CONFIG_DIR"] = old_cfg
            self.assertFalse((Path(cfg) / "manifest.toml").exists())
            self.assertGreater(status["total"], status["ready"])

    def test_stale_conda_override_falls_back_to_path_conda(self) -> None:
        data = {"conda": {"conda_exe": "/missing/conda"}}
        with mock.patch("shutil.which", side_effect=lambda name: "/usr/bin/conda" if name == "conda" else None):
            resolved = setup_status.resolve_conda(data)
        self.assertEqual("ok", resolved["state"])
        self.assertEqual("/usr/bin/conda", resolved["path"])
        self.assertEqual("PATH", resolved["source"])

    def test_configured_paths_are_reported_ready(self) -> None:
        with tempfile.TemporaryDirectory() as cfg, tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workdir = root / "work"
            dataset = root / "reads"
            workdir.mkdir()
            dataset.mkdir()
            samplesheet = workdir / "samples.csv"
            samplesheet.write_text("sample,row_id\n", encoding="utf-8")
            fasta = root / "ref.fa"
            fai = root / "ref.fa.fai"
            dict_path = root / "ref.dict"
            for path in (fasta, fai, dict_path):
                path.write_text("", encoding="utf-8")
            data = manifest_cli._load(setup_status.DEFAULT_MANIFEST)
            data["paths"]["workdir"] = str(workdir)
            data["paths"]["dataset"] = str(dataset)
            data["paths"]["reference"] = str(fasta)
            data["sample"]["samplesheet"] = str(samplesheet)
            data["sample"]["input_type"] = "fastq"
            data["reference"]["fasta"] = str(fasta)
            data["reference"]["fai"] = str(fai)
            data["reference"]["dict"] = str(dict_path)
            data["reference"]["bwa_index_ready"] = True
            old_cfg = os.environ.get("OPEN_GENOME_CONFIG_DIR")
            os.environ["OPEN_GENOME_CONFIG_DIR"] = cfg
            try:
                manifest_cli._write_manifest(Path(cfg) / "manifest.toml", data)
                status = setup_status.evaluate()
            finally:
                if old_cfg is None:
                    os.environ.pop("OPEN_GENOME_CONFIG_DIR", None)
                else:
                    os.environ["OPEN_GENOME_CONFIG_DIR"] = old_cfg
            sections = {section["name"]: {item["label"]: item for item in section["items"]} for section in status["sections"]}
            self.assertTrue(sections["Input data"]["Sequencing folder"]["ok"])
            self.assertTrue(sections["Input data"]["Samplesheet"]["ok"])
            self.assertTrue(sections["Reference"]["Reference FASTA"]["ok"])
            self.assertEqual("Illumina WGS -> BWA-MEM2 + GATK", status["recommended_plan"])

    def test_recommended_plan_detects_ont_long_reads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            samplesheet = Path(tmp) / "samples.csv"
            samplesheet.write_text(
                "sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n"
                "HG002,HG002_long,lane_1,long_reads,,,,,,,/data/HG002_ont.fastq.gz,NA,0\n",
                encoding="utf-8",
            )
            self.assertEqual(
                "ONT long reads -> minimap2 + Clair3; de novo uses Flye",
                setup_status._recommended_plan(str(samplesheet), "long_reads"),
            )


if __name__ == "__main__":
    unittest.main()
