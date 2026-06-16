#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
samplesheet=$(open_genome_manifest_get sample.samplesheet)
fasta=$(open_genome_manifest_get reference.fasta)
fai=$(open_genome_manifest_get reference.fai)
dict=$(open_genome_manifest_get reference.dict)
dbsnp=$(open_genome_manifest_get reference.dbsnp)
known_indels=$(open_genome_manifest_get reference.known_indels)
clinvar=$(open_genome_manifest_get cache.clinvar_vcf)
pharmcat_jar=$(open_genome_manifest_get cache.pharmcat_jar)
threads=$(open_genome_paths_get threads)
test -n "$threads" || threads=2

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

if test -z "$samplesheet" || ! test -f "$samplesheet"; then
	echo "Missing Open Genome samplesheet: ${samplesheet:-unset}" >&2
	echo "Run Setup -> Import sequencing files first." >&2
	exit 1
fi
if test -z "$fasta" || ! test -f "$fasta"; then
	echo "Missing reference FASTA: ${fasta:-unset}" >&2
	echo "Run Assembly -> Fetch/index GRCh38 or set a reference first." >&2
	exit 1
fi
for label_path in "samplesheet:$samplesheet" "fasta:$fasta" "fai:$fai" "dict:$dict" "dbsnp:$dbsnp" "known_indels:$known_indels" "clinvar:$clinvar" "pharmcat_jar:$pharmcat_jar"; do
	label=${label_path%%:*}
	path=${label_path#*:}
	if test -n "$path"; then
		require_safe_path "$label" "$path"
	fi
done
dbsnp=$(optional_file_path "$dbsnp")
known_indels=$(optional_file_path "$known_indels")
clinvar=$(optional_file_path "$clinvar")
pharmcat_jar=$(optional_file_path "$pharmcat_jar")
require_file "reference FASTA index (.fai)" "$fai"
require_file "reference sequence dictionary (.dict)" "$dict"
if grep -q ',fastq,' "$samplesheet"; then
	for suffix in amb ann bwt pac sa; do
		require_file "BWA index $fasta.$suffix" "$fasta.$suffix"
	done
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
enable_pgx=false
if test -n "$pharmcat_jar"; then
	require_file "PharmCAT jar" "$pharmcat_jar"
	enable_pgx=true
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
pipeline_dir="$OPEN_GENOME_BUNDLE/pipelines/open-genome"
mkdir -p "$outdir" "$workdir/nextflow-work-opengenome" "$workdir/bin"

command_file="$workdir/bin/run_open_genome_pipeline.sh"
params_file="$workdir/open-genome.params.txt"
cache_root=$(open_genome_manifest_get cache.root)
if test -z "$cache_root"; then
	cache_root="$(open_genome_cache_dir)"
	open_genome_manifest_set cache.root "$cache_root"
fi

cat >"$params_file" <<EOF
samplesheet=$samplesheet
outdir=$outdir
fasta=$fasta
fasta_fai=$fai
dict=$dict
dbsnp=$dbsnp
known_indels=$known_indels
clinvar=$clinvar
pharmcat_jar=$pharmcat_jar
cache_dir=$cache_root
enable_clinvar=$enable_clinvar
enable_pgx=$enable_pgx
allow_downloads=false
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
	printf 'nextflow run %q -profile opengenome -resume -w %q \\\n' "$pipeline_dir" "$workdir/nextflow-work-opengenome"
	printf '  --samplesheet %q \\\n' "$samplesheet"
	printf '  --outdir %q \\\n' "$outdir"
	printf '  --fasta %q \\\n' "$fasta"
	printf '  --fasta_fai %q \\\n' "$fai"
	printf '  --dict %q \\\n' "$dict"
	if test -n "$dbsnp"; then
		printf '  --dbsnp %q \\\n' "$dbsnp"
	fi
	if test -n "$known_indels"; then
		printf '  --known_indels %q \\\n' "$known_indels"
	fi
	if test -n "$clinvar"; then
		printf '  --clinvar %q \\\n' "$clinvar"
	fi
	if test -n "$pharmcat_jar"; then
		printf '  --pharmcat_jar %q \\\n' "$pharmcat_jar"
	fi
	printf '  --cache_dir %q \\\n' "$cache_root"
	printf '  --enable_clinvar %q \\\n' "$enable_clinvar"
	printf '  --enable_pgx %q \\\n' "$enable_pgx"
	printf '  --allow_downloads false\n'
} >"$command_file"
chmod 700 "$command_file"

open_genome_manifest_set workflow.engine opengenome
open_genome_manifest_set workflow.pipeline_version v1
open_genome_manifest_set workflow.native_profile opengenome
open_genome_manifest_set workflow.outdir "$outdir"
open_genome_manifest_set workflow.params_file "$params_file"
open_genome_manifest_set workflow.command_file "$command_file"

echo "Prepared Open Genome native pipeline command:"
echo "  $command_file"
echo ""
sed -n '1,120p' "$command_file"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
