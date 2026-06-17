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
	if test -z "$workdir" || open_genome_is_temp_script_path "$workdir"; then
		workdir=$(open_genome_default_workdir)
		open_genome_paths_set workdir "$workdir" || return 1
	fi
	mkdir -p "$workdir"
	printf '%s\n' "$workdir"
}

open_genome_default_workdir() {
	printf '%s\n' "$(open_genome_data_dir)/work"
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

open_genome_expand_path() {
	path=$1
	case "$path" in
		'~')
			printf '%s\n' "$HOME"
			;;
		'~'/*)
			printf '%s/%s\n' "$HOME" "${path#\~/}"
			;;
		*)
			printf '%s\n' "$path"
			;;
	esac
}

open_genome_clean_path() {
	path=$1
	if command -v python3 >/dev/null 2>&1; then
		path=$(OPEN_GENOME_RAW_PATH=$path python3 -c '
import os
import shlex

raw = os.environ.get("OPEN_GENOME_RAW_PATH", "").strip()
try:
    parts = shlex.split(raw)
except ValueError:
    parts = []
if len(parts) == 1:
    raw = parts[0]
else:
    raw = raw.strip("\"'\''")
print(raw)
')
	else
		path=${path#\"}
		path=${path%\"}
		path=${path#\'}
		path=${path%\'}
	fi
	open_genome_expand_path "$path"
}

open_genome_abs_path() {
	path=$1
	if command -v realpath >/dev/null 2>&1; then
		realpath -m "$path"
	elif test -d "$path"; then
		CDPATH= cd -- "$path" && pwd
	else
		dir=$(dirname -- "$path")
		base=$(basename -- "$path")
		printf '%s/%s\n' "$(CDPATH= cd -- "$dir" 2>/dev/null && pwd)" "$base"
	fi
}

open_genome_is_temp_script_path() {
	case "$1" in
		/tmp/open_genome_scripts*) return 0 ;;
		*) return 1 ;;
	esac
}

open_genome_is_yes_no_answer() {
	case "$1" in
		y | Y | yes | YES | n | N | no | NO) return 0 ;;
		*) return 1 ;;
	esac
}

open_genome_nearest_existing_parent() {
	path=$1
	parent=$(dirname -- "$path")
	while ! test -d "$parent"; do
		next=$(dirname -- "$parent")
		if test "$next" = "$parent"; then
			return 1
		fi
		parent=$next
	done
	printf '%s\n' "$parent"
}

open_genome_path_roots() {
	printf '%s\n' "$PWD"
	test -n "${HOME:-}" && printf '%s\n' "$HOME"
	for root in /mnt /media "/run/media/${USER:-}"; do
		test -d "$root" && printf '%s\n' "$root"
	done
}

open_genome_candidate_paths() {
	kind=$1
	open_genome_path_roots | while IFS= read -r root; do
		test -d "$root" || continue
		case "$kind" in
			dir)
				find "$root" -maxdepth 4 -type d 2>/dev/null
				;;
			file)
				find "$root" -maxdepth 5 -type f \( \
					-iname '*.fastq' -o -iname '*.fastq.gz' \
					-o -iname '*.fq' -o -iname '*.fq.gz' \
					-o -iname '*.bam' -o -iname '*.cram' \
					-o -iname '*.vcf' -o -iname '*.vcf.gz' \
					-o -iname '*.fa' -o -iname '*.fa.gz' \
					-o -iname '*.fasta' -o -iname '*.fasta.gz' \
					-o -iname '*.fna' -o -iname '*.fna.gz' \
				\) 2>/dev/null
				;;
			*)
				find "$root" -maxdepth 4 -type d 2>/dev/null
				find "$root" -maxdepth 5 -type f \( \
					-iname '*.fastq' -o -iname '*.fastq.gz' \
					-o -iname '*.fq' -o -iname '*.fq.gz' \
					-o -iname '*.bam' -o -iname '*.cram' \
					-o -iname '*.vcf' -o -iname '*.vcf.gz' \
					-o -iname '*.fa' -o -iname '*.fa.gz' \
					-o -iname '*.fasta' -o -iname '*.fasta.gz' \
					-o -iname '*.fna' -o -iname '*.fna.gz' \
				\) 2>/dev/null
				;;
		esac
	done | awk '!seen[$0]++' | sort
}

open_genome_read_path() {
	current=${1:-}
	if test -t 0 && test -t 1 && command -v bash >/dev/null 2>&1; then
		OPEN_GENOME_READ_DEFAULT=$current bash -c '
default=${OPEN_GENOME_READ_DEFAULT:-}
bind "set completion-ignore-case on" 2>/dev/null || true
bind "set show-all-if-ambiguous on" 2>/dev/null || true
bind "set mark-directories on" 2>/dev/null || true
if test -n "$default"; then
	IFS= read -e -r -i "$default" -p "> " choice || true
else
	IFS= read -e -r -p "> " choice || true
fi
printf "%s\n" "$choice"
'
	else
		if test -t 0 && test -t 1; then
			printf '> ' >&2
		fi
		read -r choice || true
		printf '%s\n' "$choice"
	fi
}

open_genome_choose_path() {
	label=$1
	kind=$2
	current=${3:-}

	echo "$label" >&2
	if test -n "$current"; then
		echo "Current: $current" >&2
	fi

	if test -n "${OPEN_GENOME_SELECTED_PATH:-}"; then
		choice=$(open_genome_clean_path "$OPEN_GENOME_SELECTED_PATH")
		open_genome_abs_path "$choice"
		return 0
	fi

	choice=
	if test -t 0 && test -t 1 && command -v fzf >/dev/null 2>&1; then
		echo "Opening picker. Press Esc to enter a path manually." >&2
		choice=$(open_genome_candidate_paths "$kind" | fzf --prompt="$label > " --height=80% --reverse --select-1 2>/dev/null) || choice=
	else
		if ! command -v fzf >/dev/null 2>&1; then
			echo "Tip: install fzf for an interactive file and folder picker." >&2
		fi
	fi

	if test -z "$choice"; then
		if test -n "$current"; then
			echo "Enter a path, or press Enter to keep the current value." >&2
		else
			echo "Enter a path to a file or folder." >&2
		fi
		if test -t 0 && test -t 1 && command -v bash >/dev/null 2>&1; then
			echo "Tab completes filesystem paths from the cursor." >&2
		fi
		choice=$(open_genome_read_path "$current")
	fi

	if test -z "$choice" && test -n "$current"; then
		choice=$current
	fi

	if test -z "$choice"; then
		return 1
	fi

	choice=$(open_genome_clean_path "$choice")
	open_genome_abs_path "$choice"
}

open_genome_existing_file_or_dir() {
	path=$1
	test -n "$path" && { test -f "$path" || test -d "$path"; }
}

open_genome_dataset_root() {
	path=$1
	if test -d "$path"; then
		open_genome_abs_path "$path"
	elif test -f "$path"; then
		dir=$(dirname -- "$path")
		echo "Selected file; using its folder: $dir" >&2
		open_genome_abs_path "$dir"
	else
		return 1
	fi
}

# Legacy paths.env (imported once by bootstrap)
OPEN_GENOME_PATHS_FILE="$OPEN_GENOME_CONFIG_DIR/paths.env"
