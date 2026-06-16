#!/usr/bin/env bash
# Create or update a conda env from modules/<id>/environment.yml.
set -euo pipefail

MODULE_ID=${1:?usage: conda_install_module.sh <module_id>}
HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export OPEN_GENOME_BUNDLE=$(CDPATH= cd -- "$HERE/.." && pwd)
ENV_YML="$OPEN_GENOME_BUNDLE/modules/$MODULE_ID/environment.yml"
LOCK_FILE=""
case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) LOCK_FILE="$OPEN_GENOME_BUNDLE/modules/$MODULE_ID/environment.lock.linux-64.txt" ;;
esac
MANIFEST_CLI="$OPEN_GENOME_BUNDLE/lib/manifest_cli.py"
DEFAULT_MANIFEST="$OPEN_GENOME_BUNDLE/manifest.default.toml"

if ! test -f "$ENV_YML"; then
	echo "Unknown module '$MODULE_ID' (missing $ENV_YML)" >&2
	exit 1
fi

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
python3 "$MANIFEST_CLI" bootstrap "$DEFAULT_MANIFEST"

# shellcheck source=conda_resolve.sh
source "$HERE/conda_resolve.sh"

echo "Environment file: $ENV_YML"
env_name=$(grep -E '^name:' "$ENV_YML" | head -n1 | sed 's/^name:[[:space:]]*//;s/[[:space:]]*$//')
if test -z "$env_name"; then
	echo "environment.yml must declare a top-level 'name:'" >&2
	exit 1
fi

if "$OG_CONDA_EXE" env list 2>/dev/null | awk '{print $1}' | grep -qx "$env_name"; then
	echo "Updating existing env: $env_name"
	"$OG_CONDA_EXE" env update -n "$env_name" -f "$ENV_YML"
else
	echo "Creating env: $env_name"
	if test -n "$LOCK_FILE" && test -f "$LOCK_FILE"; then
		echo "Using explicit lock: $LOCK_FILE"
		"$OG_CONDA_EXE" create -y -n "$env_name" --file "$LOCK_FILE"
	else
		"$OG_CONDA_EXE" env create -f "$ENV_YML"
	fi
fi

echo "Done. Activate with: $OG_CONDA_EXE activate $env_name  (conda hook required)"
