#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
command_file=$(open_genome_manifest_get workflow.command_file)
expected_root="$OPEN_GENOME_BUNDLE/pipelines"
required_engine=${OPEN_GENOME_REQUIRED_ENGINE:-}
required_engine_label=${OPEN_GENOME_REQUIRED_ENGINE_LABEL:-workflow}
needs_prepare=false
if test -z "$command_file" || ! test -f "$command_file"; then
	echo "No Open Genome command file found. Preparing the workflow now."
	needs_prepare=true
elif ! grep -Fq "$expected_root/" "$command_file"; then
	echo "Open Genome command file was prepared for a different app bundle. Refreshing it now."
	needs_prepare=true
elif test -n "$required_engine" && test "$(open_genome_manifest_get workflow.engine)" != "$required_engine"; then
	echo "Open Genome command file was prepared for a different analysis type. Refreshing it now."
	needs_prepare=true
fi

if test "$needs_prepare" = true; then
	echo ""
	bash "$HERE/prepare_open_genome_run.sh"
	command_file=$(open_genome_manifest_get workflow.command_file)
	if test -z "$command_file" || ! test -f "$command_file"; then
		echo "Could not prepare an Open Genome command file." >&2
		exit 1
	fi
fi

engine=$(open_genome_manifest_get workflow.engine)
test -n "$engine" || engine=open-genome
if test -n "$required_engine" && test "$engine" != "$required_engine"; then
	echo "The current samplesheet is not for $required_engine_label." >&2
	case "$required_engine:$engine" in
		open-genome:vcf-annotate)
			echo "You selected an existing VCF. Use Run Analysis -> Run existing VCF report, or re-import FASTQ/BAM/CRAM/long-read data for reference-based analysis." >&2
			;;
		vcf-annotate:open-genome)
			echo "You selected reads or alignments. Use Run Analysis -> Run reference-based analysis, or re-import a VCF-only folder for an existing VCF report." >&2
			;;
		*)
			echo "Re-import a single-outcome dataset from Start Here before running this action." >&2
			;;
	esac
	exit 1
fi

echo "About to run local Open Genome native pipeline:"
echo "  $command_file"
analysis_plan=$(open_genome_manifest_get workflow.recommended_plan)
if test -z "$analysis_plan"; then
	analysis_plan=$(open_genome_manifest_get sample.recommended_plan)
fi
if test -n "$analysis_plan"; then
	echo "Plan: $analysis_plan"
fi
echo ""
echo "Your genome data stays local. Public tools/databases must already be installed or cached."
printf 'Continue? [y/N] '
read -r answer || true
case "$answer" in
	y | Y | yes | YES) ;;
	*) echo "Aborted."; exit 0 ;;
esac

open_genome_resolve_conda
export PATH="$(dirname "$OG_CONDA_EXE"):$PATH"
workdir=$(open_genome_workdir)
open_genome_manifest_set workflow.last_run_dir "$workdir/nextflow-work-$engine"
"$OG_CONDA_EXE" run -n opengenome bash "$command_file"

outdir=$(open_genome_manifest_get workflow.outdir)
report_dir="$outdir/report"
open_genome_manifest_set results.report_dir "$report_dir"
if test -f "$report_dir/report_index.html"; then
	open_genome_manifest_set results.report_html "$report_dir/report_index.html"
else
	open_genome_manifest_set results.report_html "$report_dir/open_genome_report.html"
fi
open_genome_manifest_set results.findings_tsv "$report_dir/findings.tsv"
open_genome_manifest_set results.evidence_json "$report_dir/evidence.json"
