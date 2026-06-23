#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
MANIFEST_CLI="$REPO/core/tabs/open-genome/lib/manifest_cli.py"
DEFAULT_MANIFEST="$REPO/core/tabs/open-genome/manifest.default.toml"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_GENOME_CONFIG_DIR="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"

workdir="$tmp/work"
outdir="$workdir/open-genome-results"
report_dir="$outdir/report"
mkdir -p "$OPEN_GENOME_CONFIG_DIR" "$report_dir" "$outdir/annotations" "$outdir/qc" "$outdir/denovo-assembly/assembly" "$outdir/denovo-assembly/report" "$outdir/nextflow-work-opengenome/cache" "$outdir/.work/aa/bb"
printf '<html>index</html>\n' >"$report_dir/report_index.html"
printf '<html>report</html>\n' >"$report_dir/open_genome_report.html"
printf '<html>multiqc</html>\n' >"$outdir/qc/multiqc_report.html"
printf '<html>fastp</html>\n' >"$outdir/qc/fastp.demo_vcf.html"
printf '{}\n' >"$outdir/qc/fastp.demo_vcf.json"
printf '<html>fastqc</html>\n' >"$outdir/qc/demo_vcf.trimmed.R1_fastqc.html"
printf '<svg></svg>\n' >"$outdir/qc/demo_vcf.read_density.svg"
printf '>contig\nACGT\n' >"$outdir/denovo-assembly/assembly/demo.primary.fasta"
printf 'S\tcontig\tACGT\n' >"$outdir/denovo-assembly/assembly/demo.primary.gfa"
printf 'row_id\tcontig\tcircularity\n' >"$outdir/denovo-assembly/assembly/demo.circularity.tsv"
printf '<svg></svg>\n' >"$outdir/denovo-assembly/assembly/demo.assembly_graph.svg"
printf '<html>assembly</html>\n' >"$outdir/denovo-assembly/report/denovo_assembly_report.html"
cat >"$report_dir/findings.tsv" <<'EOF'
sample	row_id	section	finding
demo	demo_vcf	Variants	Variants normalized and summarized
demo	demo_vcf	Coverage	Coverage summary generated
EOF
cat >"$report_dir/evidence.json" <<'EOF'
{
  "samples": [
    {
      "sample": "demo",
      "row_id": "demo_vcf",
      "input_type": "vcf"
    }
  ],
  "files": {
    "multiqc": [
      "/tmp/multiqc_report.html"
    ]
  },
  "counts": {
    "variant_rows": 3,
    "snp_rows": 2,
    "indel_rows": 1,
    "mitochondrial_variant_rows": 1,
    "clinvar_rows": 1,
    "public_annotation_rows": 2,
    "consequence_rows": 2,
    "qc_reports": 1,
    "assembly_reports": 1
  },
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
        "assembly_reports": 1
      },
      "coverage": [
        {
          "total": {
            "mean": 30
          }
        }
      ],
      "coverage_breadth": [
        {
          "total": {
            "thresholds": {
              "10": {
                "pct": 95
              },
              "20": {
                "pct": 93
              },
              "30": {
                "pct": 91
              }
            }
          }
        }
      ]
    }
  ]
}
EOF
printf '##fileformat=VCFv4.2\n' >"$outdir/annotations/sample.annotated.vcf"
printf '##scratch\n' >"$outdir/nextflow-work-opengenome/cache/internal.vcf"
printf '<html>scratch</html>\n' >"$outdir/.work/aa/bb/denovo_assembly_report.html"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
python3 "$MANIFEST_CLI" set paths.workdir "$workdir"
python3 "$MANIFEST_CLI" set workflow.outdir "$outdir"
python3 "$MANIFEST_CLI" set workflow.recommended_plan "Existing VCF -> report-only workflow"

output=$(bash "$HERE/results_summary.sh")

grep -q "Status: READY" <<<"$output"
grep -q "Nothing is uploaded" <<<"$output"
grep -q "Plan: Existing VCF -> report-only workflow" <<<"$output"
grep -q "Open the report: Results -> Open my report" <<<"$output"
grep -q "Report snapshot" <<<"$output"
grep -q "Samples: 1 (vcf=1)" <<<"$output"
grep -q "Readiness: high-confidence review set" <<<"$output"
grep -q "Variants: 3 total rows; 2 SNPs; 1 indel; 1 mtDNA variant" <<<"$output"
grep -q "Assembly continuity reports: 1" <<<"$output"
grep -q "Report style" <<<"$output"
grep -q "Interpretation guardrails" <<<"$output"
grep -q "Raw variant files: 1" <<<"$output"
grep -q "MultiQC reports:   1" <<<"$output"
grep -q "fastp outputs:     2" <<<"$output"
grep -q "FastQC reports:    1" <<<"$output"
grep -q "Read density plots: 1" <<<"$output"
grep -q "Assembly reports:  1" <<<"$output"
grep -q "Assembly FASTA:    1" <<<"$output"
grep -q "Assembly GFA:      1" <<<"$output"
grep -q "Circularity tables: 1" <<<"$output"
grep -q "Graph previews:    1" <<<"$output"
if grep -q "nextflow-work" <<<"$output"; then
	printf 'not ok - summary should hide Nextflow scratch paths\n%s\n' "$output" >&2
	exit 1
fi
if grep -q '/\.work\|<results folder>/\.work' <<<"$output"; then
	printf 'not ok - summary should hide Nextflow work paths\n%s\n' "$output" >&2
	exit 1
fi
if [[ "$(python3 "$MANIFEST_CLI" get results.report_html)" != "$report_dir/report_index.html" ]]; then
	printf 'not ok - summary records report_html in manifest\n' >&2
	exit 1
fi

printf 'ok - results summary is user-facing and hides scratch files\n'
