#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
current=$(open_genome_paths_get reference)
path=$(open_genome_choose_path "Choose reference FASTA file or reference folder" either "$current") || {
	echo "No reference selected." >&2
	exit 1
}
if test -z "$path" || { ! test -f "$path" && ! test -d "$path"; }; then
	echo "Reference must be an existing FASTA file or folder: ${path:-unset}" >&2
	exit 1
fi
open_genome_paths_set reference "$path"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
