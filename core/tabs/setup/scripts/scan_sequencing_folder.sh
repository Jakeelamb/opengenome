#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
current=$(open_genome_paths_get dataset)
cat >&2 <<'EOF'
Choose the file or folder that best represents your data:
  - Illumina WGS: pick R1/R2 FASTQ files or their folder.
  - PacBio HiFi/CCS or ONT: pick a long-read FASTQ/BAM or its folder.
  - Existing BAM/CRAM: pick the alignment file or its folder.
  - Existing VCF: pick the VCF/VCF.GZ when you only want local reporting.

Open Genome scans the containing folder, writes a samplesheet with explicit
file paths, then run preparation chooses the recommended workflow.

For long reads, choose the analysis action later:
  - Run reference-based analysis: align to reference, QC, call variants, report.
  - Run de novo assembly: assemble reads into contigs and review assembly outputs.
EOF
selected=$(open_genome_choose_path "Choose sequencing file or folder to import" either "$current") || {
	echo "No sequencing data selected." >&2
	exit 1
}
if ! open_genome_existing_file_or_dir "$selected"; then
	echo "Sequencing data must be an existing file or folder: $selected" >&2
	exit 1
fi
input_dir=$(open_genome_dataset_root "$selected") || {
	echo "Could not resolve sequencing data folder: $selected" >&2
	exit 1
}
out="$workdir/samples/open_genome_samplesheet.csv"
python3 "$OPEN_GENOME_BUNDLE/lib/sample_scan.py" "$input_dir" --out "$out"
echo ""
echo "The recommended plan above will be used when you run analysis."
echo "Use Run Analysis -> Run reference-based analysis for FASTQ/BAM/CRAM workflows."
echo "Use Run Analysis -> Run existing VCF report for VCF-only inputs."
echo "Use Run Analysis -> Run de novo assembly when you want contigs from long reads."
python3 "$OPEN_GENOME_MANIFEST_CLI" show
