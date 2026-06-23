#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

cpus=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")
echo "Logical CPUs available: $cpus"

open_genome_bootstrap_manifest
current=$(open_genome_paths_get threads)
if test -n "$current"; then
	echo "Current CPU thread limit: $current"
else
	echo "Current CPU thread limit: default available CPUs"
fi
printf 'Optional: set CPU thread limit for Open Genome workflows (empty to clear): '
read -r threads || true
if test -n "$threads"; then
	case "$threads" in
		*[!0-9]* | 0)
			echo "CPU thread limit must be a positive whole number." >&2
			exit 1
			;;
	esac
fi
open_genome_paths_set threads "${threads:-}"
if test -n "$threads"; then
	echo "Saved CPU thread limit: $threads"
else
	echo "CPU thread limit cleared; workflows will use their default available CPUs setting."
fi
python3 "$OPEN_GENOME_MANIFEST_CLI" show
