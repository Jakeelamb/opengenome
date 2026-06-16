#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
command_file=$(open_genome_manifest_get workflow.command_file)
if test -z "$command_file" || ! test -f "$command_file"; then
	echo "No Open Genome command file found. Run 'Prepare Open Genome native run' first." >&2
	exit 1
fi

echo "About to run local Open Genome native pipeline:"
echo "  $command_file"
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
open_genome_manifest_set workflow.last_run_dir "$workdir/nextflow-work-opengenome"
"$OG_CONDA_EXE" run -n opengenome bash "$command_file"

outdir=$(open_genome_manifest_get workflow.outdir)
report_dir="$outdir/report"
open_genome_manifest_set results.report_dir "$report_dir"
open_genome_manifest_set results.report_html "$report_dir/open_genome_report.html"
open_genome_manifest_set results.findings_tsv "$report_dir/findings.tsv"
open_genome_manifest_set results.evidence_json "$report_dir/evidence.json"
