#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
export OPEN_GENOME_BUNDLE="$TABS/open-genome"

modules="
opengenome
genome_browser
denovo_assembly
"

echo "Installing/updating Open Genome tools."
echo "Open Genome uses the fewest compatible conda environments:"
echo "  - opengenome for workflows and command-line genomics tools"
echo "  - og-genome-browser for IGV, because current IGV and GATK require different Java versions"
echo "  - opengenome-denovo for hifiasm, Flye, and Verkko long-read de novo assembly"
echo "This downloads public tool packages only; it does not upload genome data."
for module in $modules; do
	echo ""
	echo "== $module =="
	bash "$OPEN_GENOME_BUNDLE/lib/conda_install_module.sh" "$module"
done

echo ""
echo "Open Genome tools are installed or updated."
