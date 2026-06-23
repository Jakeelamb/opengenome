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

printf '@read1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' | gzip -c >"$tmp/input/HG002.hifi_reads.fastq.gz"
printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/input/samples.csv"
printf 'HG002,HG002_denovo,lane_1,long_reads,,,,,,,%s,NA,0\n' "$tmp/input/HG002.hifi_reads.fastq.gz" >>"$tmp/input/samples.csv"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
python3 "$MANIFEST_CLI" set paths.workdir "$tmp/work"
python3 "$MANIFEST_CLI" set paths.dataset "$tmp/input"
python3 "$MANIFEST_CLI" set paths.threads 2
python3 "$MANIFEST_CLI" set sample.samplesheet "$tmp/input/samples.csv"
python3 "$MANIFEST_CLI" set sample.input_type long_reads

output=$(printf 'n\n' | bash "$HERE/run_denovo_assembly.sh" 2>&1)
command_file=$(python3 "$MANIFEST_CLI" get workflow.denovo_command_file)

if ! grep -q "Preparing the workflow now" <<<"$output"; then
	printf 'not ok - de novo run action auto-prepares missing workflow command\n%s\n' "$output" >&2
	exit 1
fi
if ! test -f "$command_file"; then
	printf 'not ok - auto-prepare wrote de novo command file\nexpected: %s\n' "$command_file" >&2
	exit 1
fi
if ! grep -q "denovo-assembly" "$command_file"; then
	printf 'not ok - de novo command targets denovo-assembly pipeline\n' >&2
	exit 1
fi
if ! grep -q -- "--input_dir $tmp/input" "$command_file"; then
	printf 'not ok - de novo command includes selected input folder\n' >&2
	exit 1
fi
if ! grep -q -- "--outdir $tmp/work/denovo-assembly-results" "$command_file"; then
	printf 'not ok - de novo command respects default output folder under workdir\n' >&2
	exit 1
fi
if ! grep -q -- "--max_cpus 2" "$command_file"; then
	printf 'not ok - de novo command passes manifest CPU limit to Nextflow\n' >&2
	exit 1
fi
if ! grep -q -- "--genome_size 3g" "$command_file"; then
	printf 'not ok - de novo command passes human genome-size default to Nextflow\n' >&2
	exit 1
fi
if ! grep -q -- "--flye_read_type auto" "$command_file"; then
	printf 'not ok - de novo command passes Flye read-type default to Nextflow\n' >&2
	exit 1
fi
if ! grep -q -- "--assembler hifiasm" "$command_file"; then
	printf 'not ok - HiFi de novo default should use hifiasm\n' >&2
	exit 1
fi
if ! grep -q "Plan: PacBio HiFi/CCS de novo -> hifiasm" <<<"$output"; then
	printf 'not ok - de novo run confirmation shows selected plan\n%s\n' "$output" >&2
	exit 1
fi
if ! grep -q "Aborted." <<<"$output"; then
	printf 'not ok - test should abort before launching Nextflow\n%s\n' "$output" >&2
	exit 1
fi

printf '@read1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' | gzip -c >"$tmp/input/HG002.nanopore.fastq.gz"
printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/input/ont_samples.csv"
printf 'HG002,HG002_ont,lane_1,long_reads,,,,,,,%s,NA,0\n' "$tmp/input/HG002.nanopore.fastq.gz" >>"$tmp/input/ont_samples.csv"
python3 "$MANIFEST_CLI" set sample.samplesheet "$tmp/input/ont_samples.csv"
bash "$HERE/prepare_denovo_assembly_run.sh" >"$tmp/ont-denovo.out"
if ! grep -q -- "--assembler flye" "$command_file"; then
	printf 'not ok - ONT de novo default should use Flye\n' >&2
	exit 1
fi
if ! grep -q "Plan: ONT de novo -> Flye" "$tmp/ont-denovo.out"; then
	printf 'not ok - ONT de novo prepare shows selected plan\n' >&2
	cat "$tmp/ont-denovo.out" >&2
	exit 1
fi

printf 'ok - de novo run action auto-prepares missing command file\n'
