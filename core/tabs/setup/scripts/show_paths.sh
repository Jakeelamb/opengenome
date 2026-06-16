#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

check_file() {
	label=$1
	path=$2
	next=$3
	if test -n "$path" && test -f "$path"; then
		printf 'OK      %-24s %s\n' "$label" "$path"
	else
		printf 'MISSING %-24s %s\n' "$label" "$next"
	fi
}

check_dir() {
	label=$1
	path=$2
	next=$3
	if test -n "$path" && test -d "$path"; then
		printf 'OK      %-24s %s\n' "$label" "$path"
	else
		printf 'MISSING %-24s %s\n' "$label" "$next"
	fi
}

echo "Open Genome readiness"
echo ""

workdir=$(open_genome_paths_get workdir)
dataset=$(open_genome_paths_get dataset)
samplesheet=$(open_genome_manifest_get sample.samplesheet)
fasta=$(open_genome_manifest_get reference.fasta)
fai=$(open_genome_manifest_get reference.fai)
dict=$(open_genome_manifest_get reference.dict)
command_file=$(open_genome_manifest_get workflow.command_file)
report_html=$(open_genome_manifest_get results.report_html)
clinvar=$(open_genome_manifest_get cache.clinvar_vcf)

check_dir "Work directory" "$workdir" "Setup -> Set work directory"
check_dir "Sequencing dataset" "$dataset" "Setup -> Import sequencing files"
check_file "Samplesheet" "$samplesheet" "Setup -> Import sequencing files"
check_file "Reference FASTA" "$fasta" "Assembly -> Fetch GATK GRCh38 resource bundle"
check_file "Reference FAI" "$fai" "Assembly -> Index configured GRCh38 reference"
check_file "Reference dict" "$dict" "Assembly -> Index configured GRCh38 reference"
check_file "ClinVar cache" "$clinvar" "Resources -> Set up local annotation cache"
check_file "Run command" "$command_file" "Assembly -> Prepare Open Genome native run"
check_file "HTML report" "$report_html" "Assembly -> Run / resume Open Genome native workflow"

echo ""
echo "Raw manifest values"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
