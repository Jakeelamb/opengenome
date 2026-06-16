#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR="$HERE"
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

root=$(open_genome_manifest_get conda.install_root)
if test -z "$root"; then
	root="$(open_genome_data_dir)/miniforge"
fi

miniforge_version="26.3.2-3"
expected_sha=""
case "$(uname -s)-$(uname -m)" in
	Linux-x86_64)
		asset="Miniforge3-${miniforge_version}-Linux-x86_64.sh"
		expected_sha="848194851a98903134187fbb4ab50efe87b003e0c0f808f97644b7524a62bf2c"
		;;
	Linux-aarch64 | Linux-arm64)
		asset="Miniforge3-${miniforge_version}-Linux-aarch64.sh"
		expected_sha="2c113a69297e612b01ca0f320c22a3107a11f2ab9b573d79ac868a175945ce29"
		;;
	Darwin-x86_64) asset="Miniforge3-${miniforge_version}-MacOSX-x86_64.sh" ;;
	Darwin-arm64) asset="Miniforge3-${miniforge_version}-MacOSX-arm64.sh" ;;
	*)
		echo "Unsupported platform for automatic Miniforge install: $(uname -s)-$(uname -m)" >&2
		exit 1
		;;
esac

conda_bin="$root/bin/conda"
mamba_bin="$root/bin/mamba"
if test -x "$conda_bin" || test -x "$mamba_bin"; then
	echo "Private Miniforge already exists: $root"
else
	echo "Open Genome will install private Miniforge under:"
	echo "  $root"
	echo ""
	echo "This downloads public installer code only; it does not upload genome data."
	printf 'Continue? [y/N] '
	read -r answer || true
	case "$answer" in
		y | Y | yes | YES) ;;
		*) echo "Aborted."; exit 0 ;;
	esac

	tmp_dir=$(mktemp -d)
	trap 'rm -rf "$tmp_dir"' EXIT
	installer="$tmp_dir/$asset"
		url="https://github.com/conda-forge/miniforge/releases/download/$miniforge_version/$asset"
	if command -v curl >/dev/null 2>&1; then
		curl -L --fail --show-error --output "$installer" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$installer" "$url"
	else
		echo "curl or wget is required to download Miniforge." >&2
		exit 1
	fi
		if test -n "$expected_sha"; then
			actual_sha=$(sha256sum "$installer" | awk '{print $1}')
			if test "$actual_sha" != "$expected_sha"; then
				echo "Miniforge checksum mismatch for $asset" >&2
				echo "Expected: $expected_sha" >&2
				echo "Actual:   $actual_sha" >&2
				exit 1
			fi
		else
			echo "No pinned checksum for this platform; refusing to execute downloaded installer." >&2
			exit 1
		fi
		bash "$installer" -b -p "$root"
fi

if test -x "$conda_bin"; then
	exe="$conda_bin"
elif test -x "$mamba_bin"; then
	exe="$mamba_bin"
else
	echo "Install completed but no conda/mamba executable was found under $root/bin" >&2
	exit 1
fi

open_genome_manifest_set conda.install_root "$root"
open_genome_manifest_set conda.conda_exe "$exe"
open_genome_manifest_set conda.prefer_mamba false

echo "Configured Open Genome conda executable:"
echo "  $exe"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
