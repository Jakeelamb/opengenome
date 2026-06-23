#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR="$HERE"
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

echo "Open Genome first-time setup"
echo ""
echo "This guided setup will help you:"
echo "  1. Choose the conda executable Open Genome should use."
echo "  2. Choose where outputs and temporary workflow files should live."
echo "  3. Import local sequencing files into Open Genome samplesheets."
echo "  4. Optionally point at an existing reference genome."
echo "  5. Optionally install or update Open Genome tools."
echo ""
echo "Your genome files stay on this machine. Downloads or installs happen only after you approve them."
echo ""
echo "Recommended defaults if you are not sure:"
echo "  - Illumina WGS FASTQ: Run reference-based analysis."
echo "  - PacBio HiFi/CCS or Oxford Nanopore reads:"
echo "      reference-based analysis aligns to a reference, runs QC, calls variants, and builds a report."
echo "      de novo assembly builds contigs and assembly review outputs from long reads."
echo "  - Existing BAM/CRAM: Run reference-based analysis starting from your alignment."
echo "  - Existing VCF: Run existing VCF report. No alignment or variant calling."
echo ""

if command -v conda >/dev/null 2>&1 || command -v mamba >/dev/null 2>&1; then
	echo "Existing conda-compatible executable detected."
	sh "$HERE/use_existing_conda.sh"
else
	printf 'No existing conda install was detected. Install private Miniforge/Conda now? [Y/n] '
	read -r install_conda || true
	case "${install_conda:-Y}" in
		n | N | no | NO) echo "Skipping private Miniforge." ;;
		*) bash "$HERE/install_private_miniforge.sh" ;;
	esac
fi

echo ""
printf 'Choose the output/work folder now? [Y/n] '
read -r choose_workdir || true
case "${choose_workdir:-Y}" in
	n | N | no | NO) echo "Skipping output folder selection." ;;
	*) sh "$HERE/set_workdir.sh" ;;
esac

echo ""
printf 'Import sequencing files now? [Y/n] '
read -r scan_now || true
case "${scan_now:-Y}" in
	n | N | no | NO) echo "Skipping sequencing import." ;;
	*) sh "$HERE/scan_sequencing_folder.sh" ;;
esac

echo ""
printf 'Choose an existing reference genome now? [y/N] '
read -r choose_reference || true
case "${choose_reference:-N}" in
	y | Y | yes | YES) sh "$HERE/set_reference_path.sh" ;;
	*) echo "Skipping reference selection. You can fetch or choose a reference later." ;;
esac

echo ""
printf 'Install or update Open Genome tools now? This may download conda packages. [y/N] '
read -r install_envs || true
case "${install_envs:-N}" in
	y | Y | yes | YES) bash "$HERE/conda_install_all_recommended.sh" ;;
	*) echo "Skipping tool install. You can run Start Here -> Advanced manual setup -> Install or update local tools later." ;;
esac

echo ""
echo "Setup pass complete. Read-only readiness checklist:"
sh "$HERE/show_paths.sh"
