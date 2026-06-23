#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
cache_root=$(open_genome_manifest_get cache.root)
if test -z "$cache_root"; then
	cache_root="$(open_genome_cache_dir)"
	open_genome_manifest_set cache.root "$cache_root"
fi

model_root="$cache_root/clair3-models"
hifi_dir="$model_root/hifi"
ont_dir="$model_root/r1041_e82_400bps_sup_v500"
mkdir -p "$hifi_dir" "$ont_dir"

download_model() {
	name=$1
	url=$2
	dest=$3
	echo "== Clair3 $name model =="
	for file in pileup.pt full_alignment.pt; do
		target="$dest/$file"
		if test -s "$target"; then
			echo "ready: $target"
			continue
		fi
		tmp="$target.tmp"
		echo "downloading: $url/$file"
		curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url/$file"
		test -s "$tmp"
		mv "$tmp" "$target"
	done
}

download_model hifi "https://www.bio8.cs.hku.hk/clair3/clair3_models_pytorch/hifi" "$hifi_dir"
download_model ont "https://www.bio8.cs.hku.hk/clair3/clair3_models_pytorch/r1041_e82_400bps_sup_v500" "$ont_dir"

open_genome_manifest_set cache.clair3_hifi_model "$hifi_dir"
open_genome_manifest_set cache.clair3_ont_model "$ont_dir"

echo ""
echo "Clair3 models are ready:"
echo "  PacBio HiFi: $hifi_dir"
echo "  ONT R10.4.1 sup: $ont_dir"
