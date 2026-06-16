#!/usr/bin/env sh
# Open Genome helpers. Each caller must set _OG_LIB_DIR to this file's directory before sourcing.
# Example: _OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd); . "$_OG_LIB_DIR/open_genome_lib.sh"

OPEN_GENOME_CONFIG_DIR="${OPEN_GENOME_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/open-genome}"
umask 077

if test -z "${_OG_LIB_DIR:-}"; then
	echo "open_genome_lib.sh: set _OG_LIB_DIR to the directory containing this file before sourcing." >&2
	exit 1
fi

OPEN_GENOME_TABS_ROOT=$(CDPATH= cd -- "$_OG_LIB_DIR/../.." && pwd)
OPEN_GENOME_BUNDLE="$OPEN_GENOME_TABS_ROOT/open-genome"
OPEN_GENOME_MANIFEST_CLI="$OPEN_GENOME_BUNDLE/lib/manifest_cli.py"
OPEN_GENOME_USER_MANIFEST="$OPEN_GENOME_CONFIG_DIR/manifest.toml"

open_genome_require_python() {
	if ! command -v python3 >/dev/null 2>&1; then
		echo "python3 is required (tomllib for manifest.toml)." >&2
		return 1
	fi
}

open_genome_init_manifest() {
	open_genome_require_python || return 1
	python3 "$OPEN_GENOME_MANIFEST_CLI" init "$OPEN_GENOME_BUNDLE/manifest.default.toml" || return 1
}

open_genome_bootstrap_manifest() {
	open_genome_require_python || return 1
	python3 "$OPEN_GENOME_MANIFEST_CLI" bootstrap "$OPEN_GENOME_BUNDLE/manifest.default.toml" || return 1
}

open_genome_paths_get() {
	open_genome_require_python || return 1
	python3 "$OPEN_GENOME_MANIFEST_CLI" get "paths.$1"
}

open_genome_manifest_get() {
	open_genome_require_python || return 1
	python3 "$OPEN_GENOME_MANIFEST_CLI" get "$1"
}

open_genome_paths_set() {
	open_genome_require_python || return 1
	python3 "$OPEN_GENOME_MANIFEST_CLI" set "paths.$1" "$2" || return 1
}

open_genome_manifest_set() {
	open_genome_require_python || return 1
	python3 "$OPEN_GENOME_MANIFEST_CLI" set "$1" "$2" || return 1
}

open_genome_data_dir() {
	printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/open-genome"
}

open_genome_cache_dir() {
	printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/open-genome"
}

open_genome_workdir() {
	open_genome_bootstrap_manifest || return 1
	workdir=$(open_genome_paths_get workdir)
	if test -z "$workdir"; then
		workdir="$(open_genome_data_dir)/work"
		open_genome_paths_set workdir "$workdir" || return 1
	fi
	mkdir -p "$workdir"
	printf '%s\n' "$workdir"
}

open_genome_resolve_conda() {
	open_genome_bootstrap_manifest || return 1
	# shellcheck source=../../open-genome/lib/conda_resolve.sh
	. "$OPEN_GENOME_BUNDLE/lib/conda_resolve.sh"
}

open_genome_conda_run() {
	env_name=$1
	shift
	open_genome_resolve_conda || return 1
	"$OG_CONDA_EXE" run -n "$env_name" "$@"
}

# Legacy paths.env (imported once by bootstrap)
OPEN_GENOME_PATHS_FILE="$OPEN_GENOME_CONFIG_DIR/paths.env"
