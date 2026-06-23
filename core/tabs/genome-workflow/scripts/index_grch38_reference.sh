#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
fasta=$(open_genome_manifest_get reference.fasta)
if test -z "$fasta"; then
	fasta=$(open_genome_paths_get reference)
fi
if test -z "$fasta" || ! test -f "$fasta"; then
	echo "Reference FASTA is not configured or does not exist. Fetch GRCh38 or set the reference path first." >&2
	exit 1
fi

echo "Indexing reference:"
echo "  $fasta"
echo "This writes .fai, .dict, BWA, and BWA-MEM2 index files next to the FASTA."
printf 'Continue? [y/N] '
read -r answer || true
case "$answer" in
	y | Y | yes | YES) ;;
	*) echo "Aborted."; exit 0 ;;
esac

if test -f "$fasta.fai"; then
	echo "exists: $fasta.fai"
else
	open_genome_conda_run opengenome samtools faidx "$fasta"
fi

dict="${fasta%.*}.dict"
if test "$dict" = "$fasta"; then
	dict="$fasta.dict"
fi
if test -f "$dict"; then
	echo "exists: $dict"
else
	open_genome_conda_run opengenome gatk CreateSequenceDictionary -R "$fasta" -O "$dict"
fi
if test -f "$fasta.amb" && test -f "$fasta.ann" && test -f "$fasta.bwt" && test -f "$fasta.pac" && test -f "$fasta.sa"; then
	echo "exists: BWA index files"
else
	open_genome_conda_run opengenome bwa index "$fasta"
fi
if test -f "$fasta.0123" && test -f "$fasta.bwt.2bit.64" && test -f "$fasta.amb" && test -f "$fasta.ann" && test -f "$fasta.pac"; then
	echo "exists: BWA-MEM2 index files"
else
	open_genome_conda_run opengenome bwa-mem2 index "$fasta"
fi

open_genome_manifest_set paths.reference "$fasta"
open_genome_manifest_set reference.fasta "$fasta"
open_genome_manifest_set reference.fai "$fasta.fai"
open_genome_manifest_set reference.dict "$dict"
open_genome_manifest_set reference.bwa_index_ready true
open_genome_manifest_set reference.bwa_mem2_index_ready true

echo "Reference indexing complete."
python3 "$OPEN_GENOME_MANIFEST_CLI" show
