#!/usr/bin/env python3
from __future__ import annotations

import csv
import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path

import sample_scan


class SampleScanTests(unittest.TestCase):
    def test_fastq_rows_and_sarek_conversion(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sample_L001_R1.fastq.gz").write_text("", encoding="utf-8")
            (root / "sample_L001_R2.fastq.gz").write_text("", encoding="utf-8")

            rows, warnings = sample_scan._find_fastq_rows(root)
            self.assertEqual([], warnings)
            self.assertEqual("fastq", rows[0]["input_type"])
            self.assertEqual("sample_L001", rows[0]["row_id"])
            self.assertEqual("L001", rows[0]["lane"])
            self.assertEqual(str((root / "sample_L001_R1.fastq.gz").resolve()), rows[0]["fastq_1"])

            sarek_rows = sample_scan._sarek_rows(rows)
            self.assertEqual("sample", sarek_rows[0]["sample"])
            self.assertEqual("L001", sarek_rows[0]["lane"])
            self.assertIn("fastq_2", sarek_rows[0])

    def test_alignment_vcf_and_assembly_modes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "aligned.bam").write_text("", encoding="utf-8")
            (root / "variants.vcf.gz").write_text("", encoding="utf-8")
            (root / "assembly.fasta").write_text(">x\nACGT\n", encoding="utf-8")

            self.assertEqual("alignment", sample_scan._find_alignment_rows(root)[0]["input_type"])
            self.assertEqual("vcf", sample_scan._find_vcf_rows(root)[0]["input_type"])
            self.assertEqual("assembly", sample_scan._find_assembly_rows(root)[0]["input_type"])

    def test_long_read_rows_for_reference_and_assembly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hifi_reads = root / "HG002.hifi_reads.fastq.gz"
            ont_reads = root / "HG002.nanopore.bam"
            assembly = root / "HG002.assembly.fasta"
            hifi_reads.write_text("", encoding="utf-8")
            ont_reads.write_text("", encoding="utf-8")
            assembly.write_text(">x\nACGT\n", encoding="utf-8")

            fastq_rows, warnings = sample_scan._find_fastq_rows(root)
            rows = sample_scan._find_long_read_rows(root, fastq_rows)

            self.assertEqual([], warnings)
            self.assertEqual([], fastq_rows)
            self.assertEqual(["long_reads", "long_reads"], [row["input_type"] for row in rows])
            self.assertEqual(str(hifi_reads.resolve()), rows[0]["long_reads"])
            self.assertEqual(str(ont_reads.resolve()), rows[1]["long_reads"])
            self.assertEqual("assembly", sample_scan._find_assembly_rows(root)[0]["input_type"])
            self.assertEqual([], sample_scan._find_alignment_rows(root))
            self.assertEqual(
                "ONT long reads -> minimap2 + Clair3; de novo uses Flye",
                sample_scan._recommended_plan([rows[1]]),
            )

    def test_write_open_genome_columns(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "samples.csv"
            rows = [
                {
                    "sample": "sample",
                    "row_id": "sample_vcf",
                    "lane": "lane_1",
                    "input_type": "vcf",
                    "fastq_1": "",
                    "fastq_2": "",
                    "bam": "",
                    "cram": "",
                    "vcf": "/tmp/sample.vcf.gz",
                    "assembly": "",
                    "long_reads": "",
                    "sex": "NA",
                    "status": "0",
                    "_lane": "lane_1",
                }
            ]
            sample_scan._write_samplesheet(out, rows, sample_scan.OPEN_GENOME_COLUMNS)
            with out.open("r", encoding="utf-8", newline="") as fh:
                read_rows = list(csv.DictReader(fh))
            self.assertEqual(
                [
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
                ],
                list(read_rows[0].keys()),
            )
            self.assertEqual("vcf", read_rows[0]["input_type"])
            self.assertEqual("0o600", oct(out.stat().st_mode & 0o777))

    def test_main_preserves_mixed_input_modes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as cfg:
            root = Path(tmp) / "inputs"
            root.mkdir()
            out = Path(tmp) / "samples.csv"
            (root / "sample_L001_R1.fastq.gz").write_text("", encoding="utf-8")
            (root / "sample_L001_R2.fastq.gz").write_text("", encoding="utf-8")
            (root / "sample.vcf.gz").write_text("", encoding="utf-8")
            old_cfg = os.environ.get("OPEN_GENOME_CONFIG_DIR")
            os.environ["OPEN_GENOME_CONFIG_DIR"] = cfg
            try:
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    self.assertEqual(0, sample_scan.main([str(root), "--out", str(out)]))
            finally:
                if old_cfg is None:
                    os.environ.pop("OPEN_GENOME_CONFIG_DIR", None)
                else:
                    os.environ["OPEN_GENOME_CONFIG_DIR"] = old_cfg
            with out.open("r", encoding="utf-8", newline="") as fh:
                rows = list(csv.DictReader(fh))
            self.assertEqual(["fastq", "vcf"], [row["input_type"] for row in rows])
            self.assertIn(
                "Recommended plan: Mixed inputs (fastq=1, vcf=1) -> run preparation will ask for one outcome",
                stdout.getvalue(),
            )

    def test_symlink_outside_root_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "inputs"
            root.mkdir()
            outside = Path(tmp) / "outside_R1.fastq.gz"
            outside.write_text("", encoding="utf-8")
            (root / "outside_R1.fastq.gz").symlink_to(outside)
            (root / "sample_R2.fastq.gz").write_text("", encoding="utf-8")
            rows, warnings = sample_scan._find_fastq_rows(root.resolve())
            self.assertEqual([], rows)
            self.assertTrue(any("outside selected folder" in warning for warning in warnings))


if __name__ == "__main__":
    unittest.main()
