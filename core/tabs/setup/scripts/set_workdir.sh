#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
current=$(open_genome_paths_get workdir)
if test -z "$current"; then
	current="$(open_genome_data_dir)/work"
fi
path=$(open_genome_choose_path "Choose output and work folder" dir "$current") || {
	echo "No output folder selected; keeping current setting." >&2
	exit 1
}
mkdir -p "$path"
open_genome_paths_set workdir "$path"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
