#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


class ResultDigestTests(unittest.TestCase):
    def test_digest_summarizes_evidence_and_findings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            evidence = root / "evidence.json"
            findings = root / "findings.tsv"
            evidence.write_text(
                json.dumps(
                    {
                        "samples": [{"sample": "demo", "row_id": "demo_vcf", "input_type": "vcf"}],
                        "files": {"multiqc": ["/tmp/multiqc_report.html"]},
                        "rows": [
                            {
                                "sample": "demo",
                                "row_id": "demo_vcf",
                                "counts": {
                                    "variant_rows": 3,
                                    "snp_rows": 2,
                                    "indel_rows": 1,
                                    "mitochondrial_variant_rows": 1,
                                    "clinvar_rows": 1,
                                    "public_annotation_rows": 2,
                                    "consequence_rows": 2,
                                    "qc_reports": 1,
                                    "assembly_reports": 1,
                                },
                                "coverage": [{"total": {"mean": 30}}],
                                "coverage_breadth": [
                                    {
                                        "total": {
                                            "thresholds": {
                                                "10": {"pct": 95.0},
                                                "20": {"pct": 93.0},
                                                "30": {"pct": 91.0},
                                            }
                                        }
                                    }
                                ],
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            findings.write_text(
                "sample\trow_id\tsection\tfinding\n"
                "demo\tdemo_vcf\tVariants\tVariants normalized and summarized\n"
                "demo\tdemo_vcf\tCoverage\tCoverage summary generated\n",
                encoding="utf-8",
            )

            output = subprocess.check_output(
                [
                    "python3",
                    str(HERE / "result_digest.py"),
                    "--evidence",
                    str(evidence),
                    "--findings",
                    str(findings),
                ],
                text=True,
            )

            self.assertIn("Report snapshot", output)
            self.assertIn("Samples: 1 (vcf=1)", output)
            self.assertIn("Readiness: high-confidence review set", output)
            self.assertIn("Variants: 3 total rows; 2 SNPs; 1 indel; 1 mtDNA variant", output)
            self.assertIn("Coverage: mean depth 30x; >=10x breadth 95%; >=20x 93%; >=30x 91%", output)
            self.assertIn("Public evidence: 1 ClinVar row; 2 dbSNP/gnomAD rows; 2 consequence rows", output)
            self.assertIn("Assembly continuity reports: 1", output)
            self.assertIn("Report style", output)
            self.assertIn("Finding sections", output)
            self.assertIn("Interpretation guardrails", output)


if __name__ == "__main__":
    unittest.main()
