#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
outdir=$(open_genome_manifest_get workflow.outdir)
if test -z "$outdir"; then
	outdir="$workdir/open-genome-results"
fi
engine=$(open_genome_manifest_get workflow.engine)
summary="$workdir/results/open-genome-summary.txt"
mkdir -p "$(dirname "$summary")"

{
	echo "Open Genome local results summary"
	echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	echo "Workflow engine: ${engine:-unknown}"
	echo "Output: $outdir"
	echo ""
	echo "Open Genome reports:"
	for path in "$(open_genome_manifest_get results.report_html)" "$(open_genome_manifest_get results.findings_tsv)" "$(open_genome_manifest_get results.evidence_json)"; do
		if test -n "$path" && test -f "$path"; then
			echo "$path"
		fi
	done
	find "$outdir" -type f \( -name 'open_genome_report.html' -o -name 'findings.tsv' -o -name 'evidence.json' \) 2>/dev/null | sort || true
	echo ""
	echo "MultiQC reports:"
	find "$outdir" -type f \( -name '*multiqc_report.html' -o -name 'multiqc_report.html' \) 2>/dev/null | sort || true
	echo ""
	echo "Alignment files:"
	find "$outdir" -type f \( -name '*.bam' -o -name '*.cram' \) 2>/dev/null | sort | head -n 50 || true
	echo ""
	echo "Variant files:"
	find "$outdir" -type f \( -name '*.vcf' -o -name '*.vcf.gz' -o -name '*.g.vcf.gz' \) 2>/dev/null | sort | head -n 80 || true
	echo ""
} >"$summary"

vcf=$(find "$outdir" -type f \( -name '*.annotated.vcf.gz' -o -name '*.normalized.vcf.gz' -o -name '*.vcf.gz' -o -name '*.g.vcf.gz' \) 2>/dev/null | sort | head -n 1 || true)
stats_file=""
if test -n "$vcf"; then
	stats_file="$workdir/results/$(basename "$vcf").bcftools-stats.txt"
	if open_genome_conda_run opengenome bcftools stats "$vcf" >"$stats_file"; then
		{
			echo "bcftools stats:"
			grep -E '^(SN|TSTV)' "$stats_file" | head -n 80 || true
		} >>"$summary"
	else
		echo "bcftools stats failed for $vcf" >>"$summary"
	fi
fi

multiqc_dir=$(find "$outdir" -type f \( -name '*multiqc_report.html' -o -name 'multiqc_report.html' \) -printf '%h\n' 2>/dev/null | sort | head -n 1 || true)
report_dir=$(find "$outdir" -type f -name 'open_genome_report.html' -printf '%h\n' 2>/dev/null | sort | head -n 1 || true)
open_genome_manifest_set results.summary_file "$summary"
open_genome_manifest_set results.multiqc_dir "$multiqc_dir"
open_genome_manifest_set results.variant_stats_file "$stats_file"
if test -n "$report_dir"; then
	open_genome_manifest_set results.report_dir "$report_dir"
	open_genome_manifest_set results.report_html "$report_dir/open_genome_report.html"
	open_genome_manifest_set results.findings_tsv "$report_dir/findings.tsv"
	open_genome_manifest_set results.evidence_json "$report_dir/evidence.json"
fi

cat "$summary"
echo ""
echo "Summary written to: $summary"
