#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
command_file=$(open_genome_manifest_get workflow.denovo_command_file)
expected_pipeline="$OPEN_GENOME_BUNDLE/pipelines/denovo-assembly"
needs_prepare=false
if test -z "$command_file" || ! test -f "$command_file"; then
	echo "No de novo assembly command file found. Preparing the workflow now."
	needs_prepare=true
elif ! grep -Fq "$expected_pipeline" "$command_file"; then
	echo "De novo assembly command file was prepared for a different app bundle. Refreshing it now."
	needs_prepare=true
fi

if test "$needs_prepare" = true; then
	echo ""
	bash "$HERE/prepare_denovo_assembly_run.sh"
	command_file=$(open_genome_manifest_get workflow.denovo_command_file)
	if test -z "$command_file" || ! test -f "$command_file"; then
		echo "Could not prepare a de novo assembly command file." >&2
		exit 1
	fi
fi

echo "About to run local Open Genome de novo assembly:"
echo "  $command_file"
analysis_plan=$(open_genome_manifest_get workflow.recommended_plan)
if test -n "$analysis_plan"; then
	echo "Plan: $analysis_plan"
fi
echo ""
echo "Your genome data stays local. Human de novo assembly can require high RAM, CPU, and disk space."
printf 'Continue? [y/N] '
read -r answer || true
case "$answer" in
	y | Y | yes | YES) ;;
	*) echo "Aborted."; exit 0 ;;
esac

open_genome_resolve_conda
export PATH="$(dirname "$OG_CONDA_EXE"):$PATH"
workdir=$(open_genome_workdir)
open_genome_manifest_set workflow.denovo_last_run_dir "$workdir/nextflow-work-denovo-assembly"
"$OG_CONDA_EXE" run -n opengenome-denovo bash "$command_file"

outdir=$(open_genome_manifest_get workflow.denovo_outdir)
report_dir="$outdir/report"
report_html="$report_dir/denovo_assembly_report.html"
summary_tsv="$report_dir/denovo_assembly_summary.tsv"
manifest_json="$report_dir/denovo_assembly_manifest.json"
open_genome_manifest_set workflow.outdir "$outdir"
open_genome_manifest_set results.denovo_report_dir "$report_dir"
open_genome_manifest_set results.denovo_report_html "$report_html"
open_genome_manifest_set results.denovo_summary_tsv "$summary_tsv"
open_genome_manifest_set results.denovo_manifest_json "$manifest_json"
open_genome_manifest_set results.report_dir "$report_dir"
open_genome_manifest_set results.report_html "$report_html"

echo ""
echo "De novo assembly complete."
echo "Report: $report_html"
