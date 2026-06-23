#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

clean_embedded_pipeline_scratch() {
	find core/tabs/open-genome/pipelines \
		-type d -name '.nf-test' -prune -exec rm -rf {} + 2>/dev/null || true
	find core/tabs/open-genome/pipelines \
		-type f -name '.nf-test.log' -delete 2>/dev/null || true
}

echo "== Python unit tests =="
python3 core/tabs/open-genome/lib/sample_scan_test.py
python3 core/tabs/open-genome/lib/report_compiler_test.py
python3 core/tabs/open-genome/lib/result_digest_test.py
python3 core/tabs/open-genome/lib/setup_status_test.py

echo "== Shell helper tests =="
bash core/tabs/setup/scripts/open_genome_lib_test.sh
bash core/tabs/setup/scripts/use_sample_human_dataset_test.sh
bash core/tabs/setup/scripts/run_human_validation_dataset_test.sh
bash core/tabs/setup/scripts/show_cpu_count_test.sh
bash core/tabs/setup/scripts/set_results_path_test.sh
bash core/tabs/genome-workflow/scripts/run_open_genome_test.sh
bash core/tabs/genome-workflow/scripts/run_denovo_assembly_test.sh
bash core/tabs/visualization/scripts/results_summary_test.sh
bash core/tabs/visualization/scripts/open_report_viewer_test.sh

echo "== Shell syntax =="
while IFS= read -r script; do
	bash -n "$script"
done < <(find core/tabs scripts -type f -name '*.sh' | sort)

clean_embedded_pipeline_scratch

echo "== Rust tab metadata test =="
cargo test --package opengenome_core embedded_open_genome_tabs_parse_and_resolve_scripts

echo "== Pipeline contracts =="
python3 scripts/validate-pipeline-contracts.py

nf_test_cmd=()
if command -v nf-test >/dev/null 2>&1; then
	nf_test_cmd=(nf-test)
elif test -x "$repo/.tools/bin/nf-test"; then
	nf_test_cmd=("$repo/.tools/bin/nf-test")
fi

nextflow_cmd=()
if command -v nextflow >/dev/null 2>&1; then
	nextflow_cmd=(nextflow)
elif command -v conda >/dev/null 2>&1; then
	opengenome_bin=$(conda env list 2>/dev/null | awk '$1 == "opengenome" { print $NF "/bin"; exit }')
	if test -n "$opengenome_bin" && test -x "$opengenome_bin/nextflow"; then
		nextflow_cmd=(env "PATH=$opengenome_bin:$PATH" nextflow)
	fi
fi

if test "${#nf_test_cmd[@]}" -gt 0; then
	echo "== nf-test pipeline contracts =="
	nf_test_path_prefix=""
	if command -v conda >/dev/null 2>&1; then
		opengenome_bin=$(conda env list 2>/dev/null | awk '$1 == "opengenome" { print $NF "/bin"; exit }')
		if test -n "$opengenome_bin" && test -x "$opengenome_bin/nextflow"; then
			nf_test_path_prefix="$opengenome_bin"
		fi
	fi
	for pipeline in open-genome vcf-annotate denovo-assembly; do
		if test -n "$nf_test_path_prefix"; then
			( cd "core/tabs/open-genome/pipelines/$pipeline" && PATH="$nf_test_path_prefix:$PATH" "${nf_test_cmd[@]}" test )
		else
			( cd "core/tabs/open-genome/pipelines/$pipeline" && "${nf_test_cmd[@]}" test )
		fi
	done
	clean_embedded_pipeline_scratch
else
	echo "== nf-test pipeline contracts skipped: nf-test not installed =="
fi

if test "${#nextflow_cmd[@]}" -gt 0; then
	echo "== Nextflow stub smoke =="
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	printf '>chr1\nACGTACGTACGT\n' >"$tmp/ref.fa"
	printf 'chr1\t12\t6\t12\t13\n' >"$tmp/ref.fa.fai"
	printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/vcf_samples.csv"
	printf 'toy,toy_vcf,lane_1,vcf,,,,,%s,,,NA,0\n' "$tmp/toy.vcf.gz" >>"$tmp/vcf_samples.csv"
	printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n' | gzip -c >"$tmp/toy.vcf.gz"
	NXF_HOME="$tmp/.nextflow-vcf" NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" "${nextflow_cmd[@]}" -log "$tmp/vcf.nextflow.log" run core/tabs/open-genome/pipelines/vcf-annotate \
		-profile stub \
		-stub-run \
		--input_dir "$tmp" \
		--samplesheet "$tmp/vcf_samples.csv" \
		--fasta "$tmp/ref.fa" \
		--max_cpus 2 \
		--outdir "$tmp/vcf-out" \
		-w "$tmp/vcf-work"
	test -f "$tmp/vcf-out/report/open_genome_report.html"
	printf '@read1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' >"$tmp/toy_R1.fastq"
	printf '@read1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' >"$tmp/toy_R2.fastq"
	printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/reference_samples.csv"
	printf 'toy,toy_fastq,lane_1,fastq,%s,%s,,,,,,NA,0\n' "$tmp/toy_R1.fastq" "$tmp/toy_R2.fastq" >>"$tmp/reference_samples.csv"
	NXF_HOME="$tmp/.nextflow-reference" NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" "${nextflow_cmd[@]}" -log "$tmp/reference.nextflow.log" run core/tabs/open-genome/pipelines/open-genome \
		-profile stub \
		-stub-run \
		--input_dir "$tmp" \
		--samplesheet "$tmp/reference_samples.csv" \
		--fasta "$tmp/ref.fa" \
		--fasta_fai "$tmp/ref.fa.fai" \
		--max_cpus 2 \
		--outdir "$tmp/reference-out" \
		-w "$tmp/reference-work"
	test -f "$tmp/reference-out/report/open_genome_report.html"
	printf '@read1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n' | gzip -c >"$tmp/HG002.hifi_reads.fastq.gz"
	printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/long_read_reference_samples.csv"
	printf 'HG002,HG002_lr,lane_1,long_reads,,,,,,,%s,NA,0\n' "$tmp/HG002.hifi_reads.fastq.gz" >>"$tmp/long_read_reference_samples.csv"
	NXF_HOME="$tmp/.nextflow-longref" NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" "${nextflow_cmd[@]}" -log "$tmp/longref.nextflow.log" run core/tabs/open-genome/pipelines/open-genome \
		-profile stub \
		-stub-run \
		--input_dir "$tmp" \
		--samplesheet "$tmp/long_read_reference_samples.csv" \
		--fasta "$tmp/ref.fa" \
		--fasta_fai "$tmp/ref.fa.fai" \
		--outdir "$tmp/longref-out" \
		--max_cpus 2 \
		--sequencing_platform pacbio_hifi \
		--variant_caller clair3 \
		-w "$tmp/longref-work"
	test -f "$tmp/longref-out/alignment/HG002_lr.long_read_alignment_status.tsv"
	test -f "$tmp/longref-out/variants/HG002_lr.clair3.vcf.gz"
	printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/denovo_samples.csv"
	printf 'HG002,HG002_denovo,lane_1,long_reads,,,,,,,%s,NA,0\n' "$tmp/HG002.hifi_reads.fastq.gz" >>"$tmp/denovo_samples.csv"
	NXF_HOME="$tmp/.nextflow" NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" "${nextflow_cmd[@]}" -log "$tmp/denovo.nextflow.log" run core/tabs/open-genome/pipelines/denovo-assembly \
		-profile stub \
		-stub-run \
		--input_dir "$tmp" \
		--samplesheet "$tmp/denovo_samples.csv" \
		--outdir "$tmp/denovo-out" \
		--max_cpus 2 \
		-w "$tmp/denovo-work"
	for assembler in flye verkko; do
		NXF_HOME="$tmp/.nextflow-$assembler" NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" "${nextflow_cmd[@]}" -log "$tmp/$assembler.nextflow.log" run core/tabs/open-genome/pipelines/denovo-assembly \
			-profile stub \
			-stub-run \
			--input_dir "$tmp" \
			--samplesheet "$tmp/denovo_samples.csv" \
			--outdir "$tmp/denovo-$assembler-out" \
			--max_cpus 2 \
			--assembler "$assembler" \
			--long_read_platform ont \
			-w "$tmp/denovo-$assembler-work"
		test -f "$tmp/denovo-$assembler-out/report/denovo_assembly_report.html"
		grep -q "$assembler" "$tmp/denovo-$assembler-out/report/denovo_assembly_manifest.json"
	done
else
	echo "== Nextflow stub smoke skipped: nextflow not on PATH =="
fi
