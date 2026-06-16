#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
fasta=$(open_genome_manifest_get reference.fasta)
outdir=$(open_genome_manifest_get workflow.outdir)
workdir=$(open_genome_workdir)
test -n "$outdir" || outdir="$workdir/sarek-results"

echo "Launching IGV from the optional genome browser conda environment."
echo "Reference: ${fasta:-unset}"
echo "Results:   $outdir"
echo ""
echo "Open BAM/CRAM/VCF files from the results directory inside IGV."
open_genome_conda_run og-genome-browser igv
