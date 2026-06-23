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

mkdir -p "$OPEN_GENOME_CONFIG_DIR" "$tmp/input" "$tmp/work"

printf '>chr1\nACGTACGTACGT\n' >"$tmp/ref.fa"
printf 'chr1\t12\t0\t12\t13\n' >"$tmp/ref.fa.fai"
printf '@HD\tVN:1.6\n@SQ\tSN:chr1\tLN:12\tM5:31e91beccf6059ff57c696827c0c6a4b\tUR:file:%s\n' "$tmp/ref.fa" >"$tmp/ref.dict"
printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n' | gzip -c >"$tmp/input/sample.vcf.gz"
printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/input/samples.csv"
printf 'sample,sample_vcf,lane_1,vcf,,,,,%s,,,NA,0\n' "$tmp/input/sample.vcf.gz" >>"$tmp/input/samples.csv"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
python3 "$MANIFEST_CLI" set paths.workdir "$tmp/work"
python3 "$MANIFEST_CLI" set paths.dataset "$tmp/input"
python3 "$MANIFEST_CLI" set paths.threads 3
python3 "$MANIFEST_CLI" set sample.samplesheet "$tmp/input/samples.csv"
python3 "$MANIFEST_CLI" set sample.input_type vcf
python3 "$MANIFEST_CLI" set reference.fasta "$tmp/ref.fa"
python3 "$MANIFEST_CLI" set reference.fai "$tmp/ref.fa.fai"
python3 "$MANIFEST_CLI" set reference.dict "$tmp/ref.dict"

output=$(printf 'n\n' | bash "$HERE/run_existing_vcf_report.sh" 2>&1)
command_file=$(python3 "$MANIFEST_CLI" get workflow.command_file)

if ! grep -q "Preparing the workflow now" <<<"$output"; then
	printf 'not ok - run action auto-prepares missing workflow command\n%s\n' "$output" >&2
	exit 1
fi
if ! test -f "$command_file"; then
	printf 'not ok - auto-prepare wrote command file\nexpected: %s\n' "$command_file" >&2
	exit 1
fi
if ! grep -q "vcf-annotate" "$command_file"; then
	printf 'not ok - VCF-only samplesheet routes to vcf-annotate pipeline\n' >&2
	exit 1
fi
if ! grep -q "Plan: Existing VCF -> report-only workflow" <<<"$output"; then
	printf 'not ok - run confirmation shows selected plan\n%s\n' "$output" >&2
	exit 1
fi
if ! grep -q -- "--input_dir $tmp/input" "$command_file"; then
	printf 'not ok - command includes selected input folder\n' >&2
	exit 1
fi
if ! grep -q -- "--outdir $tmp/work/open-genome-results" "$command_file"; then
	printf 'not ok - command respects default output folder under workdir\n' >&2
	exit 1
fi
if ! grep -q -- "--max_cpus 3" "$command_file"; then
	printf 'not ok - command passes manifest CPU limit to Nextflow\n' >&2
	exit 1
fi
if ! grep -q "Aborted." <<<"$output"; then
	printf 'not ok - test should abort before launching Nextflow\n%s\n' "$output" >&2
	exit 1
fi

if output=$(bash "$HERE/run_reference_analysis.sh" 2>&1); then
	printf 'not ok - reference-based action should reject VCF-only samplesheet\n%s\n' "$output" >&2
	exit 1
fi
if ! grep -q "not for reference-based analysis" <<<"$output"; then
	printf 'not ok - reference action explains VCF-only mismatch\n%s\n' "$output" >&2
	exit 1
fi

printf '@read1\nACGTACGTACGT\n+\nIIIIIIIIIIII\n' | gzip -c >"$tmp/input/sample.hifi.fastq.gz"
printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/input/long_reads.csv"
printf 'sample,sample_hifi,lane_1,long_reads,,,,,,,%s,NA,0\n' "$tmp/input/sample.hifi.fastq.gz" >>"$tmp/input/long_reads.csv"
python3 "$MANIFEST_CLI" set sample.samplesheet "$tmp/input/long_reads.csv"
python3 "$MANIFEST_CLI" set sample.input_type long_reads

if OPEN_GENOME_SEQUENCING_PLATFORM=pacbio_hifi OPEN_GENOME_VARIANT_CALLER=auto bash "$HERE/prepare_open_genome_run.sh" >"$tmp/missing-clair3.out" 2>&1; then
	printf 'not ok - long-read auto preparation fails without Clair3 models\n' >&2
	exit 1
fi
if ! grep -q "Missing Clair3 model files for pacbio_hifi" "$tmp/missing-clair3.out"; then
	printf 'not ok - missing Clair3 model error is actionable\n' >&2
	cat "$tmp/missing-clair3.out" >&2
	exit 1
fi

mkdir -p "$tmp/clair3-hifi"
printf 'model\n' >"$tmp/clair3-hifi/pileup.pt"
printf 'model\n' >"$tmp/clair3-hifi/full_alignment.pt"
python3 "$MANIFEST_CLI" set cache.clair3_hifi_model "$tmp/clair3-hifi"

OPEN_GENOME_SEQUENCING_PLATFORM=pacbio_hifi OPEN_GENOME_VARIANT_CALLER=auto bash "$HERE/prepare_open_genome_run.sh" >"$tmp/clair3-ready.out" 2>&1
command_file=$(python3 "$MANIFEST_CLI" get workflow.command_file)
if ! grep -q -- "--variant_caller auto" "$command_file"; then
	printf 'not ok - long-read prepared command keeps auto caller for pipeline routing\n' >&2
	exit 1
fi
if ! grep -q -- "--clair3_model $tmp/clair3-hifi" "$command_file"; then
	printf 'not ok - prepared command passes cached Clair3 model path\n' >&2
	exit 1
fi

printf 'ok - run action auto-prepares missing Open Genome command file\n'
