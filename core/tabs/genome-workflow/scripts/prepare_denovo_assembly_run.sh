#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
input_dir=$(open_genome_paths_get dataset)
samplesheet=$(open_genome_manifest_get sample.samplesheet)
threads=$(open_genome_paths_get threads)
test -n "$threads" || threads=16
assembler_memory="${OPEN_GENOME_DENOVO_MEMORY:-88 GB}"
assembler="${OPEN_GENOME_ASSEMBLER:-auto}"
long_read_platform="${OPEN_GENOME_LONG_READ_PLATFORM:-}"
reference_guide="${OPEN_GENOME_REFERENCE_GUIDE:-}"
genome_size="${OPEN_GENOME_DENOVO_GENOME_SIZE:-3g}"
flye_read_type="${OPEN_GENOME_FLYE_READ_TYPE:-auto}"

if test -z "$samplesheet" || ! test -f "$samplesheet"; then
	echo "Missing Open Genome samplesheet: ${samplesheet:-unset}" >&2
	echo "Run Start Here -> Start guided setup first, then choose a folder with PacBio HiFi or ONT long-read files." >&2
	exit 1
fi

denovo_rows=$(python3 - "$samplesheet" <<'PY'
import csv
import sys
from pathlib import Path

samplesheet = Path(sys.argv[1])
count = 0
missing = []
with samplesheet.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle)
    if "input_type" not in (reader.fieldnames or []):
        print("samplesheet is missing input_type column", file=sys.stderr)
        sys.exit(2)
    if "long_reads" not in (reader.fieldnames or []):
        print("samplesheet is missing long_reads column; rescan your input folder with the current Open Genome version", file=sys.stderr)
        sys.exit(2)
    for index, row in enumerate(reader, start=2):
        if (row.get("input_type") or "").strip() != "long_reads":
            continue
        reads = (row.get("long_reads") or "").strip()
        if not reads:
            missing.append(str(index))
            continue
        if not Path(reads).is_file():
            missing.append(f"{index}:{reads}")
            continue
        count += 1

if missing:
    print("long_reads rows have missing long_reads files: " + ", ".join(missing), file=sys.stderr)
    sys.exit(2)
print(count)
PY
)

if test "$denovo_rows" -eq 0; then
	echo "No de novo assembly inputs were found in the current samplesheet." >&2
	echo "Choose a folder containing long-read files named with hifi, ccs, pacbio, revio, ont, nanopore, or ultralong." >&2
	echo "Examples: HG002.hifi_reads.fastq.gz, sample.ccs.bam, sample.nanopore.fastq.gz" >&2
	exit 1
fi
if test -z "$long_read_platform"; then
	long_read_platform=$(python3 - "$samplesheet" <<'PY'
import csv
import sys
from pathlib import Path

samplesheet = Path(sys.argv[1])
platform = "hifi"
with samplesheet.open("r", encoding="utf-8", newline="") as handle:
    for row in csv.DictReader(handle):
        if (row.get("input_type") or "").strip() != "long_reads":
            continue
        reads = (row.get("long_reads") or "").lower()
        if any(token in reads for token in ("ont", "nanopore", "ultralong")):
            platform = "ont"
            break
print(platform)
PY
)
fi
if test "$assembler" = "auto"; then
	case "$long_read_platform" in
		ont) assembler=flye ;;
		*) assembler=hifiasm ;;
	esac
fi
case "$assembler:$long_read_platform" in
	hifiasm:hifi)
	analysis_plan="PacBio HiFi/CCS de novo -> hifiasm"
	;;
	flye:ont)
	analysis_plan="ONT de novo -> Flye"
	;;
	verkko:*)
	analysis_plan="Hybrid/T2T-style de novo -> Verkko"
	;;
	*)
	analysis_plan="De novo assembly -> $assembler ($long_read_platform)"
	;;
esac
for label_value in "assembler:$assembler" "long_read_platform:$long_read_platform"; do
	label=${label_value%%:*}
	value=${label_value#*:}
	case "$value" in
		*\'* | *\"* | *\`* | *\$* | *';'* | *'|'* | *'&'* | *' '*)
			echo "Unsafe characters in $label: $value" >&2
			exit 1
			;;
	esac
done
case "$flye_read_type" in
	auto | pacbio-hifi | pacbio-corr | pacbio-raw | nano-hq | nano-corr | nano-raw) ;;
	*)
		echo "Flye read type must be auto, pacbio-hifi, pacbio-corr, pacbio-raw, nano-hq, nano-corr, or nano-raw: $flye_read_type" >&2
		exit 1
		;;
esac
case "$genome_size" in
	'' | *[!0-9kKmMgG.]*)
		echo "Genome size must be a value like 3g, 3200m, or 100000: ${genome_size:-unset}" >&2
		exit 1
		;;
esac
case "$threads" in
	'' | *[!0-9]* | 0)
		echo "CPU thread limit must be a positive integer: ${threads:-unset}" >&2
		exit 1
		;;
esac
if test -n "$input_dir"; then
	case "$input_dir" in
		*\'* | *\"* | *\`* | *\$* | *';'* | *'|'* | *'&'*)
			echo "Unsafe characters in input_dir path: $input_dir" >&2
			exit 1
			;;
	esac
fi
if test -n "$reference_guide"; then
	case "$reference_guide" in
		*\'* | *\"* | *\`* | *\$* | *';'* | *'|'* | *'&'*)
			echo "Unsafe characters in reference guide path: $reference_guide" >&2
			exit 1
			;;
	esac
	if ! test -f "$reference_guide"; then
		echo "Reference guide path does not exist: $reference_guide" >&2
		exit 1
	fi
fi

outdir=$(open_genome_manifest_get workflow.denovo_outdir)
if test -z "$outdir"; then
	outdir="$workdir/denovo-assembly-results"
fi
pipeline_dir="$OPEN_GENOME_BUNDLE/pipelines/denovo-assembly"
mkdir -p "$outdir" "$workdir/nextflow-work-denovo-assembly" "$workdir/bin"

command_file="$workdir/bin/run_denovo_assembly_pipeline.sh"
params_file="$workdir/denovo-assembly.params.txt"
log_file="$workdir/denovo-assembly.nextflow.log"

cat >"$params_file" <<EOF
input_dir=$input_dir
samplesheet=$samplesheet
outdir=$outdir
max_cpus=$threads
assembler_threads=$threads
assembler_memory=$assembler_memory
assembler=$assembler
long_read_platform=$long_read_platform
reference_guide=$reference_guide
genome_size=$genome_size
flye_read_type=$flye_read_type
EOF

{
	printf '#!/usr/bin/env bash\n'
	printf 'set -euo pipefail\n'
	printf 'export NXF_HOME=%q\n' "$workdir/.nextflow"
	printf 'export NXF_CONDA_CACHEDIR=%q\n' "$workdir/nextflow-conda-cache"
	printf 'export NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}"\n'
	conda_exe=$(open_genome_manifest_get conda.conda_exe)
	if test -n "$conda_exe"; then
		printf 'export PATH=%q:$PATH\n' "$(dirname "$conda_exe")"
	fi
	printf 'nextflow -log %q run %q -profile opengenome -resume -w %q \\\n' "$log_file" "$pipeline_dir" "$workdir/nextflow-work-denovo-assembly"
	if test -n "$input_dir"; then
		printf '  --input_dir %q \\\n' "$input_dir"
	fi
	printf '  --samplesheet %q \\\n' "$samplesheet"
	printf '  --outdir %q \\\n' "$outdir"
	printf '  --max_cpus %q \\\n' "$threads"
	printf '  --assembler_threads %q \\\n' "$threads"
	printf '  --assembler_memory %q \\\n' "$assembler_memory"
	printf '  --assembler %q \\\n' "$assembler"
	printf '  --long_read_platform %q \\\n' "$long_read_platform"
	printf '  --genome_size %q \\\n' "$genome_size"
	printf '  --flye_read_type %q' "$flye_read_type"
	if test -n "$reference_guide"; then
		printf ' \\\n'
		printf '  --reference_guide %q\n' "$reference_guide"
	else
		printf '\n'
	fi
} >"$command_file"
chmod 700 "$command_file"

open_genome_manifest_set workflow.engine denovo-assembly
open_genome_manifest_set workflow.pipeline_version v1
open_genome_manifest_set workflow.denovo_outdir "$outdir"
open_genome_manifest_set workflow.denovo_params_file "$params_file"
open_genome_manifest_set workflow.denovo_command_file "$command_file"
open_genome_manifest_set workflow.recommended_plan "$analysis_plan"

echo "Prepared Open Genome de novo assembly command:"
echo "  $command_file"
echo ""
echo "Samples ready for de novo assembly: $denovo_rows"
echo "Plan: $analysis_plan"
echo "Assembler: $assembler"
echo "Platform: $long_read_platform"
echo "Supported assemblers: hifiasm, flye, verkko"
echo ""
sed -n '1,120p' "$command_file"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
