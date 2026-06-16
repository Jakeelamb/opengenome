#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
printf 'Folder containing FASTQ/BAM/CRAM/VCF files: '
read -r input_dir || true
if test -z "$input_dir"; then
	echo "No input folder provided." >&2
	exit 1
fi
out="$workdir/samples/open_genome_samplesheet.csv"
sarek_out="$workdir/samples/sarek_samplesheet.csv"
python3 "$OPEN_GENOME_BUNDLE/lib/sample_scan.py" "$input_dir" --out "$out" --sarek-out "$sarek_out"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
