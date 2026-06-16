#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR="$HERE"
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

echo "Open Genome first-time setup"
echo ""
echo "This guided setup can:"
echo "  1. Install private Miniforge/Conda for Open Genome"
echo "  2. Install the recommended local bioinformatics environment"
echo "  3. Scan your local genome data folder"
echo ""
echo "Public tools may be downloaded. Your genome files stay on this machine."
echo ""

printf 'Install or verify private Miniforge/Conda now? [Y/n] '
read -r install_conda || true
case "${install_conda:-Y}" in
	n | N | no | NO) echo "Skipping private Miniforge." ;;
	*) bash "$HERE/install_private_miniforge.sh" ;;
esac

echo ""
printf 'Install or update the recommended conda environment now? [Y/n] '
read -r install_envs || true
case "${install_envs:-Y}" in
	n | N | no | NO) echo "Skipping environment install." ;;
	*) bash "$HERE/conda_install_all_recommended.sh" ;;
esac

echo ""
printf 'Scan a local folder with FASTQ/BAM/CRAM/VCF files now? [Y/n] '
read -r scan_now || true
case "${scan_now:-Y}" in
	n | N | no | NO) echo "Skipping folder scan." ;;
	*) sh "$HERE/scan_sequencing_folder.sh" ;;
esac

echo ""
echo "Current Open Genome setup:"
sh "$HERE/show_paths.sh"
