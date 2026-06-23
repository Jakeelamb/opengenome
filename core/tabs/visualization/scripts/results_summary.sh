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
analysis_plan=$(open_genome_manifest_get workflow.recommended_plan)
if test -z "$analysis_plan"; then
	analysis_plan=$(open_genome_manifest_get sample.recommended_plan)
fi

summary="$workdir/results/open-genome-summary.txt"
mkdir -p "$(dirname "$summary")"

is_scratch_path() {
	case "$1" in
		*/nextflow-work-* | */nextflow-work-*/* | */.nextflow | */.nextflow/* | */.work | */.work/*) return 0 ;;
		*) return 1 ;;
	esac
}

print_if_file() {
	path=${1:-}
	if test -n "$path" && test -f "$path" && ! is_scratch_path "$path"; then
		printf '%s\n' "$path"
	fi
}

find_outputs() {
	if test -d "$outdir"; then
		find "$outdir" \
			\( -path '*/nextflow-work-*' -o -path '*/.nextflow' -o -path '*/.work' \) -prune -o \
			"$@" -print 2>/dev/null
	fi
}

dedupe() {
	sort -u
}

display_path() {
	path=$1
	case "$path" in
		"$outdir"/*) printf '<results folder>/%s\n' "${path#"$outdir"/}" ;;
		"$workdir"/*) printf '<work folder>/%s\n' "${path#"$workdir"/}" ;;
		*) printf '%s\n' "$path" ;;
	esac
}

mapfile -t html_reports < <({
	find_outputs -type f -name 'report_index.html'
	print_if_file "$(open_genome_manifest_get results.report_html)"
	find_outputs -type f -name 'open_genome_report.html'
	find_outputs -type f -name 'denovo_assembly_report.html'
} | awk '!seen[$0]++')
mapfile -t findings_tables < <({
	print_if_file "$(open_genome_manifest_get results.findings_tsv)"
	find_outputs -type f -name 'findings.tsv'
} | dedupe)
mapfile -t evidence_files < <({
	print_if_file "$(open_genome_manifest_get results.evidence_json)"
	find_outputs -type f -name 'evidence.json'
} | dedupe)
mapfile -t denovo_reports < <({
	print_if_file "$(open_genome_manifest_get results.denovo_report_html)"
	find_outputs -type f -name 'denovo_assembly_report.html'
} | dedupe)
mapfile -t denovo_summaries < <({
	print_if_file "$(open_genome_manifest_get results.denovo_summary_tsv)"
	find_outputs -type f -name 'denovo_assembly_summary.tsv'
} | dedupe)
mapfile -t denovo_manifests < <({
	print_if_file "$(open_genome_manifest_get results.denovo_manifest_json)"
	find_outputs -type f -name 'denovo_assembly_manifest.json'
} | dedupe)
mapfile -t multiqc_reports < <(find_outputs -type f \( -name '*multiqc_report.html' -o -name 'multiqc_report.html' \) | dedupe)
mapfile -t fastp_reports < <(find_outputs -type f \( -name 'fastp.*.html' -o -name 'fastp.*.json' \) | dedupe)
mapfile -t fastqc_reports < <(find_outputs -type f -name '*_fastqc.html' | dedupe)
mapfile -t read_density_plots < <(find_outputs -type f \( -name '*.read_density.svg' -o -name '*.read_density.png' \) | dedupe)
mapfile -t circularity_tables < <(find_outputs -type f -name '*.circularity.tsv' | dedupe)
mapfile -t assembly_graphs < <(find_outputs -type f \( -name '*.assembly_graph.svg' -o -name '*.assembly_graph.png' \) | dedupe)
mapfile -t assembly_gfas < <(find_outputs -type f \( -name '*.primary.gfa' -o -name '*.primary.gfa.gz' \) | dedupe)
mapfile -t assembly_sequences < <(find_outputs -type f \( -name '*.primary.fasta' -o -name '*.primary.fa' -o -name '*.primary.fasta.gz' -o -name '*.primary.fa.gz' \) | dedupe)
mapfile -t alignment_files < <(find_outputs -type f \( -name '*.bam' -o -name '*.cram' \) | dedupe)
mapfile -t variant_files < <(find_outputs -type f \( -name '*.annotated.vcf.gz' -o -name '*.normalized.vcf.gz' -o -name '*.vcf.gz' -o -name '*.g.vcf.gz' -o -name '*.vcf' \) | dedupe)

primary_report=${html_reports[0]:-}
primary_findings=
primary_evidence=
primary_variant=${variant_files[0]:-}
primary_denovo_report=${denovo_reports[0]:-}
primary_denovo_summary=${denovo_summaries[0]:-}
primary_denovo_manifest=${denovo_manifests[0]:-}

if test -n "$primary_report"; then
	report_dir=$(dirname -- "$primary_report")
	if test -f "$report_dir/findings.tsv"; then
		primary_findings="$report_dir/findings.tsv"
	fi
	if test -f "$report_dir/evidence.json"; then
		primary_evidence="$report_dir/evidence.json"
	fi
	open_genome_manifest_set results.report_dir "$report_dir"
	open_genome_manifest_set results.report_html "$primary_report"
fi
if test -z "$primary_findings"; then
	primary_findings=${findings_tables[0]:-}
fi
if test -z "$primary_evidence"; then
	primary_evidence=${evidence_files[0]:-}
fi
if test -n "$primary_findings"; then
	open_genome_manifest_set results.findings_tsv "$primary_findings"
fi
if test -n "$primary_evidence"; then
	open_genome_manifest_set results.evidence_json "$primary_evidence"
fi
if test -n "$primary_denovo_report"; then
	denovo_report_dir=$(dirname -- "$primary_denovo_report")
	open_genome_manifest_set results.denovo_report_dir "$denovo_report_dir"
	open_genome_manifest_set results.denovo_report_html "$primary_denovo_report"
fi
if test -n "$primary_denovo_summary"; then
	open_genome_manifest_set results.denovo_summary_tsv "$primary_denovo_summary"
fi
if test -n "$primary_denovo_manifest"; then
	open_genome_manifest_set results.denovo_manifest_json "$primary_denovo_manifest"
fi

multiqc_dir=""
if test "${#multiqc_reports[@]}" -gt 0; then
	multiqc_dir=$(dirname -- "${multiqc_reports[0]}")
fi
open_genome_manifest_set results.summary_file "$summary"
open_genome_manifest_set results.multiqc_dir "$multiqc_dir"
open_genome_manifest_set results.variant_stats_file ""

{
	echo "Open Genome results"
	echo ""
	echo "Privacy: these files are local on this computer. Nothing is uploaded."
	if test -n "$analysis_plan"; then
		echo "Plan: $analysis_plan"
	fi
	echo ""
	if test -n "$primary_report"; then
		echo "Status: READY"
		echo "Open the report: Results -> Open my report"
	else
		echo "Status: NO REPORT FOUND"
		echo "Next: Run Analysis -> Run reference-based analysis, Run existing VCF report, or Run de novo assembly"
		echo "Already have results? Start Here -> Load existing results"
	fi
	echo ""
	echo "Main files"
	if test -n "$primary_report"; then
		echo "  Report:   $(display_path "$primary_report")"
	else
		echo "  Report:   missing"
	fi
	if test -n "$primary_findings"; then
		echo "  Findings: $(display_path "$primary_findings")"
	fi
	if test -n "$primary_evidence"; then
		echo "  Evidence: $(display_path "$primary_evidence")"
	fi
	if test -n "$primary_denovo_report"; then
		echo "  Assembly report: $(display_path "$primary_denovo_report")"
	fi
	if test -n "$primary_denovo_summary"; then
		echo "  Assembly summary: $(display_path "$primary_denovo_summary")"
	fi
	if test -n "$primary_evidence"; then
		echo ""
		if ! python3 "$OPEN_GENOME_BUNDLE/lib/result_digest.py" --evidence "$primary_evidence" --findings "${primary_findings:-}" 2>/dev/null; then
			echo "Report snapshot"
			echo "  Evidence JSON was found, but it could not be summarized."
			echo "  Open the HTML report or inspect evidence.json directly."
		fi
	fi
	echo ""
	echo "Advanced files found"
	printf '  Raw variant files: %s\n' "${#variant_files[@]}"
	printf '  Alignment files:   %s\n' "${#alignment_files[@]}"
	printf '  MultiQC reports:   %s\n' "${#multiqc_reports[@]}"
	printf '  fastp outputs:     %s\n' "${#fastp_reports[@]}"
	printf '  FastQC reports:    %s\n' "${#fastqc_reports[@]}"
	printf '  Read density plots: %s\n' "${#read_density_plots[@]}"
	printf '  Assembly reports:  %s\n' "${#denovo_reports[@]}"
	printf '  Assembly FASTA:    %s\n' "${#assembly_sequences[@]}"
	printf '  Assembly GFA:      %s\n' "${#assembly_gfas[@]}"
	printf '  Circularity tables: %s\n' "${#circularity_tables[@]}"
	printf '  Graph previews:    %s\n' "${#assembly_graphs[@]}"
	echo ""
	echo "How to read this"
	echo "  Report = safest starting point."
	echo "  Variant files = evidence for review, not a diagnosis."
	echo "  Empty findings do not mean zero genetic risk."
	if test -n "$primary_variant"; then
		echo ""
		echo "Main variant file: $(display_path "$primary_variant")"
	fi
	echo ""
	echo "Next actions"
	if test -n "$primary_report"; then
		echo "  1. Open report"
		echo "  2. Read Results -> Understand report limits"
		echo "  3. Share files only if you choose"
	else
		echo "  1. Start Here -> Check what is ready"
		echo "  2. Run Analysis -> Run reference-based analysis, Run existing VCF report, or Run de novo assembly"
	fi
	echo ""
	echo "Summary saved: $(display_path "$summary")"
} >"$summary"

cat "$summary"
