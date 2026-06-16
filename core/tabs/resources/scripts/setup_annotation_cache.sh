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
clinvar_dir="$cache_root/clinvar"
mkdir -p "$clinvar_dir"

clinvar_vcf="$clinvar_dir/clinvar.GRCh38.vcf.gz"
clinvar_tbi="$clinvar_vcf.tbi"
clinvar_url="https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz"
clinvar_tbi_url="$clinvar_url.tbi"

download_atomic() {
	url=$1
	dest=$2
	tmp="$dest.tmp.$$"
	rm -f "$tmp"
	curl -L --fail --retry 3 -o "$tmp" "$url"
	if ! test -s "$tmp"; then
		echo "Downloaded file is empty: $url" >&2
		rm -f "$tmp"
		exit 1
	fi
	mv -f "$tmp" "$dest"
}

echo "Open Genome annotation cache"
echo "Cache: $cache_root"
echo ""
echo "This downloads public annotation data only. User genome data is not uploaded."
printf 'Download/update ClinVar GRCh38 VCF now? [Y/n] '
read -r answer || true
case "${answer:-Y}" in
	n | N | no | NO) echo "Skipping ClinVar download." ;;
	*)
		download_atomic "$clinvar_url" "$clinvar_vcf"
		download_atomic "$clinvar_tbi_url" "$clinvar_tbi"
		if ! gzip -t "$clinvar_vcf"; then
			echo "ClinVar VCF failed gzip validation: $clinvar_vcf" >&2
			exit 1
		fi
		open_genome_manifest_set cache.clinvar_vcf "$clinvar_vcf"
		open_genome_manifest_set cache.clinvar_tbi "$clinvar_tbi"
		;;
esac

dbsnp=$(open_genome_manifest_get reference.dbsnp)
if test -n "$dbsnp"; then
	open_genome_manifest_set cache.dbsnp_vcf "$dbsnp"
	if test -f "$dbsnp.tbi"; then
		open_genome_manifest_set cache.dbsnp_tbi "$dbsnp.tbi"
	fi
fi

release_manifest="$cache_root/cache_manifest.json"
clinvar_sha=""
clinvar_tbi_sha=""
if test -f "$clinvar_vcf"; then
	clinvar_sha=$(sha256sum "$clinvar_vcf" | awk '{print $1}')
fi
if test -f "$clinvar_tbi"; then
	clinvar_tbi_sha=$(sha256sum "$clinvar_tbi" | awk '{print $1}')
fi
cat >"$release_manifest" <<EOF
{
  "generated_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "clinvar_vcf": "$clinvar_vcf",
  "clinvar_source": "$clinvar_url",
  "clinvar_sha256": "$clinvar_sha",
  "clinvar_tbi_sha256": "$clinvar_tbi_sha",
  "dbsnp_vcf": "$dbsnp"
}
EOF
open_genome_manifest_set cache.release_manifest "$release_manifest"

echo ""
echo "Cache manifest: $release_manifest"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
