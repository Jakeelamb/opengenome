#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

bundle_dir=$(open_genome_manifest_get reference.bundle_dir)
if test -z "$bundle_dir"; then
	bundle_dir="$(open_genome_data_dir)/references/gatk_grch38"
fi
mkdir -p "$bundle_dir"

# The older genomics-public-data bucket now denies anonymous object reads.
# Broad's public references mirror exposes the same hg38/v0 resource path.
base_url="https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0"
files="
Homo_sapiens_assembly38.fasta
Homo_sapiens_assembly38.fasta.fai
Homo_sapiens_assembly38.dict
Homo_sapiens_assembly38.dbsnp138.vcf.gz
Homo_sapiens_assembly38.dbsnp138.vcf.gz.tbi
Homo_sapiens_assembly38.known_indels.vcf.gz
Homo_sapiens_assembly38.known_indels.vcf.gz.tbi
Mills_and_1000G_gold_standard.indels.hg38.vcf.gz
Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi
1000G_phase1.snps.high_confidence.hg38.vcf.gz
1000G_phase1.snps.high_confidence.hg38.vcf.gz.tbi
"

echo "Open Genome will download public GATK GRCh38 resources into:"
echo "  $bundle_dir"
echo ""
echo "This can require substantial disk space and time. User genome data is not uploaded."
printf 'Continue? [y/N] '
read -r answer || true
case "$answer" in
	y | Y | yes | YES) ;;
	*) echo "Aborted."; exit 0 ;;
esac

download_one() {
	name=$1
	dest="$bundle_dir/$name"
	if test -s "$dest"; then
		if case "$dest" in *.gz) gzip -t "$dest" ;; *) true ;; esac; then
			echo "exists: $dest"
			return 0
		fi
		echo "invalid existing file, redownloading: $dest"
	fi
	url="$base_url/$name"
	tmp="$dest.tmp.$$"
	rm -f "$tmp"
	echo "download: $url"
	if command -v curl >/dev/null 2>&1; then
		curl -L --fail --show-error --output "$tmp" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$tmp" "$url"
	else
		echo "curl or wget is required." >&2
		exit 1
	fi
	if ! test -s "$tmp"; then
		echo "Downloaded file is empty: $url" >&2
		rm -f "$tmp"
		exit 1
	fi
	case "$tmp" in
		*.gz.*) ;;
		*.gz)
			if ! gzip -t "$tmp"; then
				echo "Downloaded gzip failed validation: $url" >&2
				rm -f "$tmp"
				exit 1
			fi
			;;
	esac
	mv -f "$tmp" "$dest"
}

for file in $files; do
	download_one "$file"
done

fasta="$bundle_dir/Homo_sapiens_assembly38.fasta"
open_genome_manifest_set paths.reference "$fasta"
open_genome_manifest_set reference.profile "gatk_grch38"
open_genome_manifest_set reference.bundle_dir "$bundle_dir"
open_genome_manifest_set reference.fasta "$fasta"
open_genome_manifest_set reference.fai "$bundle_dir/Homo_sapiens_assembly38.fasta.fai"
open_genome_manifest_set reference.dict "$bundle_dir/Homo_sapiens_assembly38.dict"
open_genome_manifest_set reference.dbsnp "$bundle_dir/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
open_genome_manifest_set reference.known_indels "$bundle_dir/Homo_sapiens_assembly38.known_indels.vcf.gz"
open_genome_manifest_set reference.mills_indels "$bundle_dir/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"
open_genome_manifest_set reference.thousand_genomes_snps "$bundle_dir/1000G_phase1.snps.high_confidence.hg38.vcf.gz"

echo "GRCh38 resource bundle paths recorded."
python3 "$OPEN_GENOME_MANIFEST_CLI" show
