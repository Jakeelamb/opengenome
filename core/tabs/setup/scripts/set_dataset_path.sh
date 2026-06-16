#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
current=$(open_genome_paths_get dataset)
path=$(open_genome_choose_path "Choose sequencing data file or folder" either "$current") || {
	echo "No sequencing data selected." >&2
	exit 1
}
if ! open_genome_existing_file_or_dir "$path"; then
	echo "Sequencing data must be an existing file or folder: $path" >&2
	exit 1
fi
dataset=$(open_genome_dataset_root "$path") || {
	echo "Could not resolve sequencing data folder: $path" >&2
	exit 1
}
open_genome_paths_set dataset "$dataset"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
