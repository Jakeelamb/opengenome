#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


class ReportCompilerTests(unittest.TestCase):
    def test_counts_are_attributed_per_row_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            inputs = root / "inputs"
            out = root / "out"
            inputs.mkdir()
            samplesheet = root / "samples.csv"
            samplesheet.write_text(
                "sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,sex,status\n"
                "alice,alice_L001,L001,vcf,,,,,/tmp/alice.vcf.gz,,NA,0\n"
                "bob,bob_L001,L001,vcf,,,,,/tmp/bob.vcf.gz,,NA,0\n",
                encoding="utf-8",
            )
            (inputs / "alice_L001.variant_summary.tsv").write_text(
                "chrom\tpos\tid\tref\talt\tgt\nchr1\t10\trs1\tA\tG\t0/1\n",
                encoding="utf-8",
            )
            (inputs / "bob_L001.variant_summary.tsv").write_text(
                "chrom\tpos\tid\tref\talt\tgt\nchr1\t10\trs1\tA\tG\t0/1\nchr1\t20\trs2\tC\tT\t0/1\n",
                encoding="utf-8",
            )
            (inputs / "alice_L001.clinvar.matches.tsv").write_text("chrom\tpos\tid\tref\talt\tgt\n", encoding="utf-8")
            (inputs / "bob_L001.clinvar.matches.tsv").write_text(
                "chrom\tpos\tid\tref\talt\tgt\nchr1\t20\trs2\tC\tT\t0/1\n",
                encoding="utf-8",
            )
            (inputs / "bob_L001.pharmcat_status.tsv").write_text(
                "row_id\tsample\tstate\tmessage\nbob_L001\tbob\tskipped\tPharmCAT jar not configured\n",
                encoding="utf-8",
            )

            subprocess.run(
                [
                    "python3",
                    str(HERE / "report_compiler.py"),
                    "--input-dir",
                    str(inputs),
                    "--out-dir",
                    str(out),
                    "--samplesheet",
                    str(samplesheet),
                ],
                check=True,
            )

            evidence = json.loads((out / "evidence.json").read_text(encoding="utf-8"))
            by_row = {row["row_id"]: row["counts"] for row in evidence["rows"]}
            self.assertEqual(1, by_row["alice_L001"]["variant_rows"])
            self.assertEqual(2, by_row["bob_L001"]["variant_rows"])
            self.assertEqual(0, by_row["alice_L001"]["clinvar_rows"])
            self.assertEqual(1, by_row["bob_L001"]["clinvar_rows"])
            with (out / "findings.tsv").open("r", encoding="utf-8", newline="") as fh:
                findings = list(csv.DictReader(fh, delimiter="\t"))
            variant_counts = {
                row["row_id"]: row["count"]
                for row in findings
                if row["finding"] == "Variants normalized and summarized"
            }
            self.assertEqual({"alice_L001": "1", "bob_L001": "2"}, variant_counts)
            self.assertEqual("0o600", oct((out / "evidence.json").stat().st_mode & 0o777))


if __name__ == "__main__":
    unittest.main()
