#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$HERE
# shellcheck source=open_genome_lib.sh
. "$HERE/open_genome_lib.sh"

assert_eq() {
	local expected=$1
	local actual=$2
	local label=$3
	if [[ "$actual" != "$expected" ]]; then
		printf 'not ok - %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
		exit 1
	fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/folder with spaces"

assert_eq "$tmp/folder with spaces" "$(open_genome_clean_path "$tmp/folder\\ with\\ spaces")" "cleans shell-escaped spaces"
assert_eq "$tmp/folder with spaces" "$(open_genome_clean_path "\"$tmp/folder with spaces\"")" "cleans quoted paths"
assert_eq "$HOME/example" "$(open_genome_clean_path "~/example")" "expands home shorthand"
assert_eq "$tmp/folder with spaces" "$(printf '%s\n' "$tmp/folder with spaces" | open_genome_read_path "")" "reads fallback paths with spaces"
assert_eq "$tmp/folder with spaces" "$(OPEN_GENOME_SELECTED_PATH="$tmp/folder with spaces" open_genome_choose_path "test path" dir "" 2>/dev/null)" "uses native picker selected path"

open_genome_is_temp_script_path "/tmp/open_genome_scriptsabc-0/setup/scripts/y" || {
	printf 'not ok - detects temporary script paths\n' >&2
	exit 1
}
open_genome_is_yes_no_answer "y" || {
	printf 'not ok - detects accidental yes/no path input\n' >&2
	exit 1
}
if open_genome_is_yes_no_answer "$tmp/folder with spaces"; then
	printf 'not ok - does not treat real paths as yes/no answers\n' >&2
	exit 1
fi
assert_eq "$tmp" "$(open_genome_nearest_existing_parent "$tmp/new/child/work")" "finds nearest existing parent"

printf 'ok - open_genome_lib path helpers\n'
