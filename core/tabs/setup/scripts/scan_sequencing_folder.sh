#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
current=$(open_genome_paths_get dataset)
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
sarek_out="$workdir/samples/sarek_samplesheet.csv"
python3 "$OPEN_GENOME_BUNDLE/lib/sample_scan.py" "$input_dir" --out "$out" --sarek-out "$sarek_out"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
