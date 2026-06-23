#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
MANIFEST_CLI="$REPO/core/tabs/open-genome/lib/manifest_cli.py"
DEFAULT_MANIFEST="$REPO/core/tabs/open-genome/manifest.default.toml"
RESULTS_SUMMARY="$REPO/core/tabs/visualization/scripts/results_summary.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_GENOME_CONFIG_DIR="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST" >/dev/null

output=$(sh "$HERE/use_sample_human_dataset.sh")

grep -q "Demo outputs generated" <<<"$output"
grep -q "Next: Results -> Open my report" <<<"$output"

workdir=$(python3 "$MANIFEST_CLI" get paths.workdir)
dataset=$(python3 "$MANIFEST_CLI" get paths.dataset)
samplesheet=$(python3 "$MANIFEST_CLI" get sample.samplesheet)
reference=$(python3 "$MANIFEST_CLI" get reference.fasta)
outdir=$(python3 "$MANIFEST_CLI" get workflow.outdir)
report_html=$(python3 "$MANIFEST_CLI" get results.report_html)
findings=$(python3 "$MANIFEST_CLI" get results.findings_tsv)
evidence=$(python3 "$MANIFEST_CLI" get results.evidence_json)
denovo_report=$(python3 "$MANIFEST_CLI" get results.denovo_report_html)
denovo_summary=$(python3 "$MANIFEST_CLI" get results.denovo_summary_tsv)
denovo_manifest=$(python3 "$MANIFEST_CLI" get results.denovo_manifest_json)

assert_file() {
	local path=$1
	local label=$2
	if [[ ! -s "$path" ]]; then
		printf 'not ok - missing %s: %s\n' "$label" "$path" >&2
		exit 1
	fi
}

[[ "$workdir" == "$XDG_DATA_HOME/open-genome/work" ]]
[[ "$dataset" == "$workdir/demo/sequencing" ]]
[[ "$outdir" == "$workdir/open-genome-results" ]]
assert_file "$dataset/OpenGenome_demo_HG002.vcf.gz" "demo VCF"
assert_file "$samplesheet" "samplesheet"
assert_file "$reference" "reference"
assert_file "$report_html" "report HTML"
assert_file "$findings" "findings TSV"
assert_file "$evidence" "evidence JSON"
assert_file "$outdir/reference-germline/report/report_index.html" "reference germline report"
assert_file "$outdir/existing-vcf/report/report_index.html" "existing VCF report"
assert_file "$outdir/reference-germline/qc/fastp.OpenGenome_demo_HG002_illumina.json" "fastp JSON"
assert_file "$outdir/reference-germline/qc/fastp.OpenGenome_demo_HG002_illumina.html" "fastp HTML"
assert_file "$outdir/reference-germline/qc/OpenGenome_demo_HG002_illumina.trimmed.R1_fastqc.html" "R1 FastQC HTML"
assert_file "$outdir/reference-germline/qc/OpenGenome_demo_HG002_illumina.trimmed.R2_fastqc.html" "R2 FastQC HTML"
assert_file "$outdir/reference-germline/qc/OpenGenome_demo_HG002_illumina.read_density.svg" "reference read density plot"
assert_file "$denovo_report" "de novo assembly report"
assert_file "$denovo_summary" "de novo assembly summary"
assert_file "$denovo_manifest" "de novo assembly manifest"
assert_file "$outdir/denovo-assembly/assembly/OpenGenome_demo_HG002_hifi.primary.fasta" "assembly FASTA"
assert_file "$outdir/denovo-assembly/assembly/OpenGenome_demo_HG002_hifi.primary.gfa" "assembly GFA"
assert_file "$outdir/denovo-assembly/assembly/OpenGenome_demo_HG002_hifi.circularity.tsv" "assembly circularity table"
assert_file "$outdir/denovo-assembly/assembly/OpenGenome_demo_HG002_hifi.read_density.tsv" "assembly read density table"
assert_file "$outdir/denovo-assembly/assembly/OpenGenome_demo_HG002_hifi.read_density.svg" "assembly read density plot"
assert_file "$outdir/denovo-assembly/assembly/OpenGenome_demo_HG002_hifi.assembly_graph.svg" "assembly graph preview"

grep -q "fastp.OpenGenome_demo_HG002_illumina.json" "$outdir/reference-germline/report/report_index.html"
grep -q "OpenGenome_demo_HG002_illumina.read_density.svg" "$outdir/reference-germline/report/report_index.html"
grep -q "Circularity table" "$denovo_report"
grep -q "Read density plot" "$denovo_report"
grep -q "Assembly graph preview" "$denovo_report"

summary=$(bash "$RESULTS_SUMMARY")
grep -q "Status: READY" <<<"$summary"
grep -q "Raw variant files: 4" <<<"$summary"
grep -q "Assembly reports:  1" <<<"$summary"
grep -q "Report:   <results folder>/report/report_index.html" <<<"$summary"
grep -q "Assembly report: <results folder>/denovo-assembly/report/denovo_assembly_report.html" <<<"$summary"

printf 'ok - sample data action generates preview reports and results summary\n'
