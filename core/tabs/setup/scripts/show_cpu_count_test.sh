#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
MANIFEST_CLI="$REPO/core/tabs/open-genome/lib/manifest_cli.py"
DEFAULT_MANIFEST="$REPO/core/tabs/open-genome/manifest.default.toml"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_GENOME_CONFIG_DIR="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST" >/dev/null
python3 "$MANIFEST_CLI" set paths.threads 4

output=$(printf '8\n' | sh "$HERE/show_cpu_count.sh")
grep -q "Current CPU thread limit: 4" <<<"$output"
grep -q "Saved CPU thread limit: 8" <<<"$output"
[[ "$(python3 "$MANIFEST_CLI" get paths.threads)" == "8" ]]

output=$(printf '\n' | sh "$HERE/show_cpu_count.sh")
grep -q "Current CPU thread limit: 8" <<<"$output"
grep -q "CPU thread limit cleared" <<<"$output"
[[ -z "$(python3 "$MANIFEST_CLI" get paths.threads)" ]]

printf 'ok - CPU thread limit action shows current value and saves changes\n'
