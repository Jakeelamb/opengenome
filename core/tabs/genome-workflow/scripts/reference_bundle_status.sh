#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

echo "Reference profile: $(open_genome_manifest_get reference.profile)"
echo "Bundle dir:        $(open_genome_manifest_get reference.bundle_dir)"
echo "FASTA:             $(open_genome_manifest_get reference.fasta)"
echo "FAI:               $(open_genome_manifest_get reference.fai)"
echo "DICT:              $(open_genome_manifest_get reference.dict)"
echo "BWA ready:         $(open_genome_manifest_get reference.bwa_index_ready)"
echo "BWA-MEM2 ready:    $(open_genome_manifest_get reference.bwa_mem2_index_ready)"
echo "dbSNP:             $(open_genome_manifest_get reference.dbsnp)"
echo "Known indels:      $(open_genome_manifest_get reference.known_indels)"
echo "Mills indels:      $(open_genome_manifest_get reference.mills_indels)"
echo "1000G SNPs:        $(open_genome_manifest_get reference.thousand_genomes_snps)"
echo ""

missing=0
for key in fasta fai dict dbsnp known_indels mills_indels thousand_genomes_snps; do
	path=$(open_genome_manifest_get "reference.$key")
	if test -z "$path" || ! test -f "$path"; then
		echo "missing: reference.$key (${path:-unset})"
		missing=1
	fi
done

fasta=$(open_genome_manifest_get reference.fasta)
if test -n "$fasta"; then
	for suffix in amb ann bwt pac sa; do
		if ! test -f "$fasta.$suffix"; then
			echo "missing: BWA index $fasta.$suffix"
			missing=1
		fi
	done
	for suffix in 0123 bwt.2bit.64 amb ann pac; do
		if ! test -f "$fasta.$suffix"; then
			echo "missing: BWA-MEM2 index $fasta.$suffix"
			missing=1
		fi
	done
fi

if test "$missing" -eq 0; then
	echo "Reference bundle looks ready."
else
	echo "Reference bundle is incomplete."
fi
