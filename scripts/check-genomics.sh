#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

echo "== Python unit tests =="
python3 core/tabs/open-genome/lib/sample_scan_test.py
python3 core/tabs/open-genome/lib/report_compiler_test.py

echo "== Shell syntax =="
while IFS= read -r script; do
	bash -n "$script"
done < <(find core/tabs -type f -name '*.sh' | sort)

echo "== Rust tab metadata test =="
cargo test --package linutil_core embedded_open_genome_tabs_parse_and_resolve_scripts

nextflow_cmd=()
if command -v nextflow >/dev/null 2>&1; then
	nextflow_cmd=(nextflow)
elif command -v conda >/dev/null 2>&1 && conda run -n opengenome nextflow -version >/dev/null 2>&1; then
	nextflow_cmd=(conda run -n opengenome nextflow)
fi

if test "${#nextflow_cmd[@]}" -gt 0; then
	echo "== Nextflow stub smoke =="
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	printf '>chr1\nACGTACGTACGT\n' >"$tmp/ref.fa"
	printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,sex,status\n' >"$tmp/samples.csv"
	printf 'toy,toy_vcf,lane_1,vcf,,,,,%s,,NA,0\n' "$tmp/toy.vcf.gz" >>"$tmp/samples.csv"
	printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n' | gzip -c >"$tmp/toy.vcf.gz"
	NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" "${nextflow_cmd[@]}" run core/tabs/open-genome/pipelines/open-genome \
		-profile stub \
		-stub-run \
		--samplesheet "$tmp/samples.csv" \
		--fasta "$tmp/ref.fa" \
		--outdir "$tmp/out" \
		-w "$tmp/work"
else
	echo "== Nextflow stub smoke skipped: nextflow not on PATH =="
fi
