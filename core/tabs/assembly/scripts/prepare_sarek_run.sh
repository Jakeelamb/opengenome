#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
samplesheet=$(open_genome_manifest_get sample.sarek_samplesheet)
if test -z "$samplesheet"; then
	samplesheet=$(open_genome_manifest_get sample.samplesheet)
fi
fasta=$(open_genome_manifest_get reference.fasta)
fai=$(open_genome_manifest_get reference.fai)
dict=$(open_genome_manifest_get reference.dict)
dbsnp=$(open_genome_manifest_get reference.dbsnp)
known_indels=$(open_genome_manifest_get reference.known_indels)
known_snps=$(open_genome_manifest_get reference.thousand_genomes_snps)
version=$(open_genome_manifest_get workflow.sarek_version)
runtime=$(open_genome_manifest_get workflow.sarek_runtime)
if test -z "$runtime"; then
	runtime=$(open_genome_manifest_get workflow.runtime)
fi
threads=$(open_genome_paths_get threads)
test -n "$version" || version="3.8.1"
test -n "$runtime" || runtime="conda"
case "$runtime" in
	conda | docker | singularity | apptainer) ;;
	*)
		echo "Unsupported Sarek profile '$runtime'; using conda." >&2
		runtime=conda
		;;
esac

for required in samplesheet fasta fai dict dbsnp known_indels known_snps; do
	eval "value=\${$required}"
	if test -z "$value" || ! test -f "$value"; then
		echo "Missing required $required: ${value:-unset}" >&2
		echo "Run Setup scan + GRCh38 fetch/index actions first." >&2
		exit 1
	fi
done

for path in "$samplesheet" "$fasta" "$fai" "$dict" "$dbsnp" "$known_indels" "$known_snps"; do
	case "$path" in
		*" "*) echo "Warning: Sarek may reject paths with spaces: $path" ;;
	esac
done

outdir=$(open_genome_manifest_get workflow.outdir)
if test -z "$outdir"; then
	outdir="$workdir/sarek-results"
fi
mkdir -p "$outdir" "$workdir/nextflow-work" "$workdir/bin"

command_file="$workdir/bin/run_sarek_open_genome.sh"
params_file="$workdir/sarek-open-genome.params.txt"

cat >"$params_file" <<EOF
input=$samplesheet
outdir=$outdir
fasta=$fasta
fasta_fai=$fai
dict=$dict
bwa=$fasta
dbsnp=$dbsnp
dbsnp_tbi=$dbsnp.tbi
known_indels=$known_indels
known_indels_tbi=$known_indels.tbi
known_snps=$known_snps
known_snps_tbi=$known_snps.tbi
tools=haplotypecaller
aligner=bwa-mem
genome=GATK.GRCh38
igenomes_ignore=true
save_mapped=true
save_output_as_bam=false
skip_tools=multiqc
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
	printf 'nextflow run nf-core/sarek -r %q -profile %q -resume -w %q \\\n' "$version" "$runtime" "$workdir/nextflow-work"
	printf '  --input %q \\\n' "$samplesheet"
	printf '  --outdir %q \\\n' "$outdir"
	printf '  --fasta %q \\\n' "$fasta"
	printf '  --fasta_fai %q \\\n' "$fai"
	printf '  --dict %q \\\n' "$dict"
	printf '  --bwa %q \\\n' "$fasta"
	printf '  --dbsnp %q \\\n' "$dbsnp"
	printf '  --dbsnp_tbi %q \\\n' "$dbsnp.tbi"
	printf '  --known_indels %q \\\n' "$known_indels"
	printf '  --known_indels_tbi %q \\\n' "$known_indels.tbi"
	printf '  --known_snps %q \\\n' "$known_snps"
	printf '  --known_snps_tbi %q \\\n' "$known_snps.tbi"
	printf '  --tools haplotypecaller \\\n'
	printf '  --aligner bwa-mem \\\n'
	printf '  --genome GATK.GRCh38 \\\n'
	printf '  --igenomes_ignore \\\n'
	printf '  --save_mapped \\\n'
	printf '  --skip_tools multiqc\n'
} >"$command_file"
chmod 700 "$command_file"

open_genome_manifest_set paths.reference "$fasta"
open_genome_manifest_set workflow.engine sarek
open_genome_manifest_set workflow.sarek_version "$version"
open_genome_manifest_set workflow.sarek_runtime "$runtime"
open_genome_manifest_set workflow.outdir "$outdir"
open_genome_manifest_set workflow.params_file "$params_file"
open_genome_manifest_set workflow.command_file "$command_file"

echo "Prepared Sarek command:"
echo "  $command_file"
echo ""
sed -n '1,120p' "$command_file"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
