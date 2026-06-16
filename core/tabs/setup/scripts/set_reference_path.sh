#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
printf 'Reference genome path (FASTA or directory): '
read -r path || true
if test -z "$path" || { ! test -f "$path" && ! test -d "$path"; }; then
	echo "Reference path must be an existing FASTA file or directory: ${path:-unset}" >&2
	exit 1
fi
open_genome_paths_set reference "$path"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
