#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

ready_count=0
total_count=0

pass() {
	label=$1
	detail=$2
	total_count=$((total_count + 1))
	ready_count=$((ready_count + 1))
	printf '[x] %-28s %s\n' "$label" "$detail"
}

miss() {
	label=$1
	detail=$2
	total_count=$((total_count + 1))
	printf '[ ] %-28s %s\n' "$label" "$detail"
}

info() {
	label=$1
	detail=$2
	printf '[-] %-28s %s\n' "$label" "$detail"
}

check_file() {
	label=$1
	path=$2
	next=$3
	if test -n "$path" && test -f "$path"; then
		pass "$label" "$path"
	else
		miss "$label" "$next"
	fi
}

check_dir() {
	label=$1
	path=$2
	next=$3
	if test -n "$path" && test -d "$path"; then
		pass "$label" "$path"
	else
		miss "$label" "$next"
	fi
}

check_value() {
	label=$1
	value=$2
	next=$3
	if test -n "$value"; then
		pass "$label" "$value"
	else
		miss "$label" "$next"
	fi
}

check_bool_true() {
	label=$1
	value=$2
	next=$3
	if test "$value" = "True" || test "$value" = "true"; then
		pass "$label" "ready"
	else
		miss "$label" "$next"
	fi
}

check_conda() {
	exe=$(open_genome_manifest_get conda.conda_exe 2>/dev/null || true)
	if test -n "$exe"; then
		if test -x "$exe"; then
			pass "Conda available" "$exe"
		else
			miss "Conda available" "Setup -> Install private Miniforge/Conda, or fix conda.conda_exe"
		fi
	elif command -v conda >/dev/null 2>&1; then
		pass "Conda available" "$(command -v conda)"
	else
		miss "Conda available" "Setup -> Install private Miniforge/Conda"
	fi
}

check_conda_env() {
	if command -v conda >/dev/null 2>&1 && conda env list 2>/dev/null | awk '{print $1}' | grep -qx 'opengenome'; then
		pass "Open Genome env" "opengenome"
	else
		exe=$(open_genome_manifest_get conda.conda_exe 2>/dev/null || true)
		if test -n "$exe" && test -x "$exe" && "$exe" env list 2>/dev/null | awk '{print $1}' | grep -qx 'opengenome'; then
			pass "Open Genome env" "opengenome"
		else
			miss "Open Genome env" "Setup -> Install / update: Open Genome env"
		fi
	fi
}

workdir=$(open_genome_paths_get workdir)
dataset=$(open_genome_paths_get dataset)
samplesheet=$(open_genome_manifest_get sample.samplesheet)
sample_type=$(open_genome_manifest_get sample.input_type)
reference_path=$(open_genome_paths_get reference)
fasta=$(open_genome_manifest_get reference.fasta)
fai=$(open_genome_manifest_get reference.fai)
dict=$(open_genome_manifest_get reference.dict)
dbsnp=$(open_genome_manifest_get reference.dbsnp)
bwa_ready=$(open_genome_manifest_get reference.bwa_index_ready)
params_file=$(open_genome_manifest_get workflow.params_file)
command_file=$(open_genome_manifest_get workflow.command_file)
outdir=$(open_genome_manifest_get workflow.outdir)
report_html=$(open_genome_manifest_get results.report_html)
findings_tsv=$(open_genome_manifest_get results.findings_tsv)
evidence_json=$(open_genome_manifest_get results.evidence_json)
clinvar=$(open_genome_manifest_get cache.clinvar_vcf)
clinvar_tbi=$(open_genome_manifest_get cache.clinvar_tbi)

echo "Open Genome setup checklist"
echo ""

echo "Machine"
check_conda
check_conda_env
check_dir "Output folder" "$workdir" "Setup -> Choose output folder"
threads=$(open_genome_paths_get threads)
if test -n "$threads"; then
	info "CPU thread cap" "$threads"
else
	info "CPU thread cap" "optional; defaults to available CPUs"
fi
echo ""

echo "Input data"
check_dir "Sequencing folder" "$dataset" "Setup -> Choose sequencing data"
check_file "Samplesheet" "$samplesheet" "Setup -> Import sequencing files"
check_value "Detected input type" "$sample_type" "Setup -> Import sequencing files"
echo ""

echo "Reference"
if test -n "$reference_path" && { test -f "$reference_path" || test -d "$reference_path"; }; then
	pass "Chosen reference path" "$reference_path"
else
	miss "Chosen reference path" "Setup -> Choose reference genome"
fi
check_file "Reference FASTA" "$fasta" "Assembly -> Fetch GATK GRCh38 resource bundle"
check_file "Reference FAI" "$fai" "Assembly -> Index configured GRCh38 reference"
check_file "Reference dict" "$dict" "Assembly -> Index configured GRCh38 reference"
check_bool_true "BWA index" "$bwa_ready" "Assembly -> Index configured GRCh38 reference"
check_file "dbSNP VCF" "$dbsnp" "Assembly -> Fetch GATK GRCh38 resource bundle"
echo ""

echo "Annotation cache"
check_file "ClinVar VCF" "$clinvar" "Resources -> Set up local annotation cache"
check_file "ClinVar index" "$clinvar_tbi" "Resources -> Set up local annotation cache"
echo ""

echo "Workflow"
check_dir "Workflow output folder" "$outdir" "Assembly -> Prepare Open Genome native run"
check_file "Params file" "$params_file" "Assembly -> Prepare Open Genome native run"
check_file "Run command" "$command_file" "Assembly -> Prepare Open Genome native run"
echo ""

echo "Results"
check_file "HTML report" "$report_html" "Assembly -> Run / resume Open Genome native workflow"
check_file "Findings table" "$findings_tsv" "Assembly -> Run / resume Open Genome native workflow"
check_file "Evidence JSON" "$evidence_json" "Assembly -> Run / resume Open Genome native workflow"

echo ""
printf 'Ready: %s/%s checks complete\n' "$ready_count" "$total_count"
if test "$ready_count" -eq "$total_count"; then
	echo "Status: ready to review results."
else
	echo "Status: run the listed setup actions for unchecked items."
fi

echo ""
echo "Saved locations"
printf '  Work folder:       %s\n' "${workdir:-not set}"
printf '  Sequencing folder: %s\n' "${dataset:-not set}"
printf '  Samplesheet:       %s\n' "${samplesheet:-not set}"
printf '  Reference:         %s\n' "${fasta:-${reference_path:-not set}}"
printf '  Workflow output:   %s\n' "${outdir:-not set}"
printf '  Report:            %s\n' "${report_html:-not set}"
