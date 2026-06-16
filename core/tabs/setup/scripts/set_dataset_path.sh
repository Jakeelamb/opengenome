#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
printf 'Sequencing dataset path (reads or run folder): '
read -r path || true
if test -z "$path" || ! test -d "$path"; then
	echo "Dataset path must be an existing directory: ${path:-unset}" >&2
	exit 1
fi
open_genome_paths_set dataset "$path"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
