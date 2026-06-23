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
fasta=$(open_genome_manifest_get reference.fasta)
fai=$(open_genome_manifest_get reference.fai)
dict=$(open_genome_manifest_get reference.dict)
dbsnp=$(open_genome_manifest_get reference.dbsnp)
known_indels=$(open_genome_manifest_get reference.known_indels)
clinvar=$(open_genome_manifest_get cache.clinvar_vcf)
gnomad=$(open_genome_manifest_get cache.gnomad_vcf)
gnomad_tbi=$(open_genome_manifest_get cache.gnomad_tbi)
vep_cache=$(open_genome_manifest_get cache.vep_cache)
snpeff_db=$(open_genome_manifest_get cache.snpeff_db)
snpeff_config=$(open_genome_manifest_get cache.snpeff_config)
pharmcat_jar=$(open_genome_manifest_get cache.pharmcat_jar)
threads=$(open_genome_paths_get threads)
test -n "$threads" || threads=2
sequencing_platform=${OPEN_GENOME_SEQUENCING_PLATFORM:-}
short_read_aligner=${OPEN_GENOME_SHORT_READ_ALIGNER:-bwa-mem2}
long_read_aligner=${OPEN_GENOME_LONG_READ_ALIGNER:-auto}
variant_caller=${OPEN_GENOME_VARIANT_CALLER:-auto}
deepvariant_model=${OPEN_GENOME_DEEPVARIANT_MODEL:-auto}
deepvariant_bin=${OPEN_GENOME_DEEPVARIANT_BIN:-run_deepvariant}
clair3_model=${OPEN_GENOME_CLAIR3_MODEL:-}
clair3_platform=${OPEN_GENOME_CLAIR3_PLATFORM:-auto}
cache_root=$(open_genome_manifest_get cache.root)
if test -z "$cache_root"; then
	cache_root="$(open_genome_cache_dir)"
	open_genome_manifest_set cache.root "$cache_root"
fi

missing=0
require_file() {
	label=$1
	path=$2
	if test -z "$path" || ! test -f "$path"; then
		echo "Missing $label: ${path:-unset}" >&2
		missing=1
	fi
}
require_safe_path() {
	label=$1
	path=$2
	case "$path" in
		*\'* | *\"* | *\`* | *\$* | *';'* | *'|'* | *'&'*)
			echo "Unsafe characters in $label path: $path" >&2
			missing=1
			;;
	esac
}
optional_file_path() {
	case "${1:-}" in
		"" | true | false | null) printf '' ;;
		*) printf '%s' "$1" ;;
	esac
}

safe_mode() {
	case "$2" in
		*\'* | *\"* | *\`* | *\$* | *';'* | *'|'* | *'&'* | *' '*)
			echo "Unsafe characters in $1: $2" >&2
			missing=1
			;;
	esac
}

if test -z "$samplesheet" || ! test -f "$samplesheet"; then
	echo "Missing Open Genome samplesheet: ${samplesheet:-unset}" >&2
	echo "Run Start Here -> Start guided setup first." >&2
	exit 1
fi
if test -z "$fasta" || ! test -f "$fasta"; then
	echo "Missing reference FASTA: ${fasta:-unset}" >&2
	echo "Use Start Here -> Advanced manual setup -> Download reference genome, or choose a reference first." >&2
	exit 1
fi
if ! workflow_kind=$(python3 - "$samplesheet" <<'PY'
import csv
import sys
from collections import Counter
from pathlib import Path

samplesheet = Path(sys.argv[1])
counts = Counter()
with samplesheet.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle)
    if "input_type" not in (reader.fieldnames or []):
        print("samplesheet is missing input_type column", file=sys.stderr)
        sys.exit(2)
    for row in reader:
        input_type = (row.get("input_type") or "").strip()
        if input_type:
            counts[input_type] += 1

if not counts:
    print("samplesheet has no runnable rows", file=sys.stderr)
    sys.exit(2)

allowed_reference = {"fastq", "long_reads", "alignment"}
if set(counts) <= allowed_reference:
    print("open-genome")
elif set(counts) == {"vcf"}:
    print("vcf-annotate")
elif "assembly" in counts:
    print("assembly rows are report artifacts, not reference-analysis inputs; run denovo-assembly for long_reads or rescan/select a VCF/FASTQ/BAM folder", file=sys.stderr)
    sys.exit(2)
else:
    detail = ", ".join(f"{key}={value}" for key, value in sorted(counts.items()))
    print(f"samplesheet mixes incompatible workflow outcomes ({detail}); create a single-outcome samplesheet before preparing a run", file=sys.stderr)
    sys.exit(2)
PY
); then
	exit 1
fi
if test -z "$sequencing_platform"; then
	sequencing_platform=$(python3 - "$samplesheet" <<'PY'
import csv
import sys
from pathlib import Path

samplesheet = Path(sys.argv[1])
platform = "illumina"
with samplesheet.open("r", encoding="utf-8", newline="") as handle:
    for row in csv.DictReader(handle):
        input_type = (row.get("input_type") or "").strip()
        reads = (row.get("long_reads") or "").lower()
        if input_type == "long_reads":
            platform = "ont" if any(token in reads for token in ("ont", "nanopore", "ultralong")) else "pacbio_hifi"
            break
print(platform)
PY
)
fi
analysis_plan=$(open_genome_manifest_get sample.recommended_plan)
if test -z "$analysis_plan"; then
	case "$workflow_kind:$sequencing_platform" in
		open-genome:illumina)
			analysis_plan="Illumina WGS -> BWA-MEM2 + GATK"
			;;
		open-genome:pacbio_hifi)
			analysis_plan="PacBio HiFi/CCS -> pbmm2 + Clair3; de novo uses hifiasm"
			;;
		open-genome:ont)
			analysis_plan="ONT long reads -> minimap2 + Clair3; de novo uses Flye"
			;;
		vcf-annotate:*)
			analysis_plan="Existing VCF -> report-only workflow"
			;;
		*)
			analysis_plan="$workflow_kind with $sequencing_platform inputs"
			;;
	esac
fi
if test "$workflow_kind" = "open-genome"; then
	case "$variant_caller:$sequencing_platform" in
		auto:pacbio_hifi | clair3:pacbio_hifi)
			if test -z "$clair3_model"; then
				clair3_model=$(open_genome_manifest_get cache.clair3_hifi_model)
			fi
			if test -z "$clair3_model"; then
				clair3_model="$cache_root/clair3-models/hifi"
			fi
			;;
		auto:ont | clair3:ont)
			if test -z "$clair3_model"; then
				clair3_model=$(open_genome_manifest_get cache.clair3_ont_model)
			fi
			if test -z "$clair3_model"; then
				clair3_model="$cache_root/clair3-models/r1041_e82_400bps_sup_v500"
			fi
			;;
	esac
fi
for label_path in "input_dir:$input_dir" "samplesheet:$samplesheet" "fasta:$fasta" "fai:$fai" "dict:$dict" "dbsnp:$dbsnp" "known_indels:$known_indels" "clinvar:$clinvar" "gnomad:$gnomad" "gnomad_tbi:$gnomad_tbi" "vep_cache:$vep_cache" "snpeff_db:$snpeff_db" "snpeff_config:$snpeff_config" "pharmcat_jar:$pharmcat_jar"; do
	label=${label_path%%:*}
	path=${label_path#*:}
	if test -n "$path"; then
		require_safe_path "$label" "$path"
	fi
done
safe_mode sequencing_platform "$sequencing_platform"
safe_mode short_read_aligner "$short_read_aligner"
safe_mode long_read_aligner "$long_read_aligner"
safe_mode variant_caller "$variant_caller"
safe_mode deepvariant_model "$deepvariant_model"
safe_mode deepvariant_bin "$deepvariant_bin"
safe_mode clair3_platform "$clair3_platform"
safe_mode max_cpus "$threads"
case "$threads" in
	'' | *[!0-9]* | 0)
		echo "CPU thread limit must be a positive integer: ${threads:-unset}" >&2
		missing=1
		;;
esac
if test -n "$clair3_model"; then
	require_safe_path clair3_model "$clair3_model"
fi
dbsnp=$(optional_file_path "$dbsnp")
known_indels=$(optional_file_path "$known_indels")
clinvar=$(optional_file_path "$clinvar")
gnomad=$(optional_file_path "$gnomad")
gnomad_tbi=$(optional_file_path "$gnomad_tbi")
vep_cache=$(optional_file_path "$vep_cache")
snpeff_db=$(optional_file_path "$snpeff_db")
snpeff_config=$(optional_file_path "$snpeff_config")
pharmcat_jar=$(optional_file_path "$pharmcat_jar")
require_file "reference FASTA index (.fai)" "$fai"
if test "$workflow_kind" = "open-genome"; then
	require_file "reference sequence dictionary (.dict)" "$dict"
fi
if test "$workflow_kind" = "open-genome" && grep -q ',fastq,' "$samplesheet"; then
	if test "$short_read_aligner" = "bwa-mem2"; then
		for suffix in 0123 bwt.2bit.64 amb ann pac; do
			require_file "BWA-MEM2 index $fasta.$suffix" "$fasta.$suffix"
		done
	else
		for suffix in amb ann bwt pac sa; do
			require_file "BWA index $fasta.$suffix" "$fasta.$suffix"
		done
	fi
fi
if test -n "$dbsnp"; then
	require_file "dbSNP VCF index" "$dbsnp.tbi"
fi
if test -n "$known_indels"; then
	require_file "known indels VCF index" "$known_indels.tbi"
fi
enable_clinvar=false
if test -n "$clinvar"; then
	require_file "ClinVar VCF" "$clinvar"
	require_file "ClinVar VCF index" "$clinvar.tbi"
	enable_clinvar=true
fi
if test -n "$gnomad"; then
	require_file "gnomAD VCF" "$gnomad"
	if test -z "$gnomad_tbi"; then
		gnomad_tbi="$gnomad.tbi"
	fi
	require_file "gnomAD VCF index" "$gnomad_tbi"
fi
if test -n "$vep_cache" && ! test -d "$vep_cache"; then
	echo "Missing VEP cache directory: $vep_cache" >&2
	missing=1
fi
if test -n "$snpeff_config"; then
	require_file "SnpEff config" "$snpeff_config"
fi
enable_pgx=false
if test -n "$pharmcat_jar"; then
	require_file "PharmCAT jar" "$pharmcat_jar"
	enable_pgx=true
fi
if test "$workflow_kind" = "open-genome"; then
	case "$variant_caller:$sequencing_platform" in
		auto:pacbio_hifi | clair3:pacbio_hifi | auto:ont | clair3:ont)
			if test -z "$clair3_model" || ! test -s "$clair3_model/pileup.pt" || ! test -s "$clair3_model/full_alignment.pt"; then
				echo "Missing Clair3 model files for $sequencing_platform: ${clair3_model:-unset}" >&2
				echo "Run Start Here -> Advanced manual setup -> Download Clair3 models, or set OPEN_GENOME_CLAIR3_MODEL to a directory containing pileup.pt and full_alignment.pt." >&2
				missing=1
			fi
			;;
	esac
fi
if test "$missing" -ne 0; then
	echo "" >&2
	echo "Open Genome run is not ready. Fix the missing files above, then prepare again." >&2
	exit 1
fi

outdir=$(open_genome_manifest_get workflow.outdir)
if test -z "$outdir"; then
	outdir="$workdir/open-genome-results"
fi
pipeline_dir="$OPEN_GENOME_BUNDLE/pipelines/$workflow_kind"
nextflow_work="$workdir/nextflow-work-$workflow_kind"
mkdir -p "$outdir" "$nextflow_work" "$workdir/bin"

command_file="$workdir/bin/run_open_genome_pipeline.sh"
params_file="$workdir/open-genome.params.txt"
log_file="$workdir/open-genome.nextflow.log"

cat >"$params_file" <<EOF
input_dir=$input_dir
samplesheet=$samplesheet
outdir=$outdir
max_cpus=$threads
fasta=$fasta
fasta_fai=$fai
dict=$dict
dbsnp=$dbsnp
known_indels=$known_indels
clinvar=$clinvar
gnomad=$gnomad
gnomad_tbi=$gnomad_tbi
vep_cache=$vep_cache
snpeff_db=$snpeff_db
snpeff_config=$snpeff_config
pharmcat_jar=$pharmcat_jar
cache_dir=$cache_root
enable_clinvar=$enable_clinvar
enable_pgx=$enable_pgx
allow_downloads=false
sequencing_platform=$sequencing_platform
short_read_aligner=$short_read_aligner
long_read_aligner=$long_read_aligner
variant_caller=$variant_caller
deepvariant_model=$deepvariant_model
deepvariant_bin=$deepvariant_bin
clair3_model=$clair3_model
clair3_platform=$clair3_platform
EOF

{
	printf '#!/usr/bin/env bash\n'
	printf 'set -euo pipefail\n'
		printf 'export NXF_HOME=%q\n' "$workdir/.nextflow"
		printf 'export NXF_CONDA_CACHEDIR=%q\n' "$workdir/nextflow-conda-cache"
		printf 'export NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}"\n'
conda_exe=$(open_genome_manifest_get conda.conda_exe)
if test -n "$conda_exe"; then
		env_prefix=$("$conda_exe" env list 2>/dev/null | awk '$1 == "opengenome" { print $NF; exit }' || true)
		if test -n "$env_prefix" && test -d "$env_prefix/bin"; then
			printf 'export PATH=%q:$PATH\n' "$env_prefix/bin"
		fi
		printf 'export PATH=%q:$PATH\n' "$(dirname "$conda_exe")"
	fi
	printf 'nextflow -log %q run %q -profile opengenome -resume -w %q \\\n' "$log_file" "$pipeline_dir" "$nextflow_work"
	if test -n "$input_dir"; then
		printf '  --input_dir %q \\\n' "$input_dir"
	fi
	printf '  --samplesheet %q \\\n' "$samplesheet"
	printf '  --outdir %q \\\n' "$outdir"
	printf '  --max_cpus %q \\\n' "$threads"
	printf '  --fasta %q \\\n' "$fasta"
	printf '  --fasta_fai %q \\\n' "$fai"
	if test "$workflow_kind" = "open-genome"; then
		printf '  --dict %q \\\n' "$dict"
	fi
	if test -n "$dbsnp"; then
		printf '  --dbsnp %q \\\n' "$dbsnp"
	fi
	if test -n "$known_indels"; then
		printf '  --known_indels %q \\\n' "$known_indels"
	fi
	if test -n "$clinvar"; then
		printf '  --clinvar %q \\\n' "$clinvar"
	fi
	if test -n "$gnomad"; then
		printf '  --gnomad %q \\\n' "$gnomad"
	fi
	if test -n "$gnomad_tbi"; then
		printf '  --gnomad_tbi %q \\\n' "$gnomad_tbi"
	fi
	if test -n "$vep_cache"; then
		printf '  --vep_cache %q \\\n' "$vep_cache"
	fi
	if test -n "$snpeff_db"; then
		printf '  --snpeff_db %q \\\n' "$snpeff_db"
	fi
	if test -n "$snpeff_config"; then
		printf '  --snpeff_config %q \\\n' "$snpeff_config"
	fi
	if test -n "$pharmcat_jar"; then
		printf '  --pharmcat_jar %q \\\n' "$pharmcat_jar"
	fi
	printf '  --cache_dir %q \\\n' "$cache_root"
	printf '  --enable_clinvar %q \\\n' "$enable_clinvar"
	printf '  --enable_pgx %q \\\n' "$enable_pgx"
	printf '  --allow_downloads false \\\n'
	printf '  --sequencing_platform %q \\\n' "$sequencing_platform"
	printf '  --short_read_aligner %q \\\n' "$short_read_aligner"
	printf '  --long_read_aligner %q \\\n' "$long_read_aligner"
	printf '  --variant_caller %q \\\n' "$variant_caller"
	printf '  --deepvariant_model %q \\\n' "$deepvariant_model"
	printf '  --deepvariant_bin %q \\\n' "$deepvariant_bin"
	if test -n "$clair3_model"; then
		printf '  --clair3_model %q \\\n' "$clair3_model"
	fi
	printf '  --clair3_platform %q\n' "$clair3_platform"
} >"$command_file"
chmod 700 "$command_file"

open_genome_manifest_set workflow.engine "$workflow_kind"
open_genome_manifest_set workflow.pipeline_version v1
open_genome_manifest_set workflow.native_profile opengenome
open_genome_manifest_set workflow.outdir "$outdir"
open_genome_manifest_set workflow.params_file "$params_file"
open_genome_manifest_set workflow.command_file "$command_file"
open_genome_manifest_set workflow.recommended_plan "$analysis_plan"

echo "Prepared Open Genome native pipeline command:"
echo "  $command_file"
echo ""
echo "Workflow: $workflow_kind"
echo "Plan: $analysis_plan"
sed -n '1,120p' "$command_file"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
