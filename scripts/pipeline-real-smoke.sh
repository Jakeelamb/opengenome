#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

if ! command -v conda >/dev/null 2>&1; then
	echo "== Real pipeline smoke skipped: conda not on PATH =="
	exit 0
fi

conda_env_bin() {
	env_name=$1
	conda env list 2>/dev/null | awk -v name="$env_name" '$1 == name { print $NF "/bin"; exit }'
}

opengenome_bin=$(conda_env_bin opengenome)
denovo_bin=$(conda_env_bin opengenome-denovo)

if test -z "$opengenome_bin" || ! test -x "$opengenome_bin/nextflow"; then
	echo "== Real pipeline smoke skipped: opengenome conda environment is not installed =="
	exit 0
fi
if ! PATH="$opengenome_bin:$PATH" bash -c 'for tool in nextflow samtools gatk bwa-mem2 fastp fastqc multiqc mosdepth bcftools bgzip tabix wget; do command -v "$tool" >/dev/null || exit 1; done'; then
	echo "== Real pipeline smoke skipped: opengenome environment is missing required smoke-test tools =="
	exit 0
fi

echo "== Real Nextflow smoke =="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

download_if_missing() {
	url=$1
	dest=$2
	if test -s "$dest"; then
		return 0
	fi
	mkdir -p "$(dirname "$dest")"
	PATH="$opengenome_bin:$PATH" wget -q -O "$dest.tmp" "$url"
	test -s "$dest.tmp"
	mv "$dest.tmp" "$dest"
}

python3 - "$tmp" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
seq = ("ACGT" * 300)[:1000]
(root / "ref.fa").write_text(
    ">chr1\n" + "\n".join(seq[i : i + 80] for i in range(0, len(seq), 80)) + "\n",
    encoding="utf-8",
)

r1 = seq[100:200]
r2 = seq[250:350][::-1].translate(str.maketrans("ACGT", "TGCA"))
(root / "sample_R1.fastq").write_text(f"@r1/1\n{r1}\n+\n{'I' * len(r1)}\n", encoding="utf-8")
(root / "sample_R2.fastq").write_text(f"@r1/2\n{r2}\n+\n{'I' * len(r2)}\n", encoding="utf-8")

(root / "toy.vcf").write_text(
    "\n".join(
        [
            "##fileformat=VCFv4.2",
            "##contig=<ID=chr1,length=1000>",
            '##INFO=<ID=ANN,Number=.,Type=String,Description="Functional annotations: Allele|Annotation|Annotation_Impact|Gene_Name">',
            '##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">',
            "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ttoy",
            "chr1\t5\trsToy\tA\tC\t60\tPASS\tANN=C|missense_variant|MODERATE|GENE1\tGT\t0/1",
            "",
        ]
    ),
    encoding="utf-8",
)
PY

PATH="$opengenome_bin:$PATH" bash -c "
	set -euo pipefail
	samtools faidx '$tmp/ref.fa'
	gatk CreateSequenceDictionary -R '$tmp/ref.fa' -O '$tmp/ref.dict' >/dev/null
	bwa-mem2 index '$tmp/ref.fa' >/dev/null
	bgzip -c '$tmp/toy.vcf' > '$tmp/toy.vcf.gz'
	tabix -f -p vcf '$tmp/toy.vcf.gz'
"

printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/vcf_samples.csv"
printf 'toy,toy_vcf,lane_1,vcf,,,,,%s,,,NA,0\n' "$tmp/toy.vcf.gz" >>"$tmp/vcf_samples.csv"

PATH="$opengenome_bin:$PATH" nextflow -log "$tmp/vcf.nextflow.log" run core/tabs/open-genome/pipelines/vcf-annotate \
	-profile opengenome \
	--input_dir "$tmp" \
	--samplesheet "$tmp/vcf_samples.csv" \
	--outdir "$tmp/vcf-out" \
	--max_cpus 2 \
	--fasta "$tmp/ref.fa" \
	-w "$tmp/vcf-work"

test -f "$tmp/vcf-out/report/report_index.html"
test -f "$tmp/vcf-out/report/findings.tsv"
test -f "$tmp/vcf-out/report/evidence.json"
test -f "$tmp/vcf-out/variants/toy_vcf.normalized.vcf.gz"
grep -q 'missense_variant' "$tmp/vcf-out/annotations/toy_vcf.consequence_summary.tsv"

printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/reference_samples.csv"
printf 'toy,toy_fastq,lane_1,fastq,%s,%s,,,,,,NA,0\n' "$tmp/sample_R1.fastq" "$tmp/sample_R2.fastq" >>"$tmp/reference_samples.csv"

PATH="$opengenome_bin:$PATH" nextflow -log "$tmp/reference.nextflow.log" run core/tabs/open-genome/pipelines/open-genome \
	-profile opengenome \
	--input_dir "$tmp" \
	--samplesheet "$tmp/reference_samples.csv" \
	--outdir "$tmp/reference-out" \
	--max_cpus 2 \
	--fasta "$tmp/ref.fa" \
	--fasta_fai "$tmp/ref.fa.fai" \
	--dict "$tmp/ref.dict" \
	--variant_caller gatk \
	-w "$tmp/reference-work"

test -f "$tmp/reference-out/alignment/toy_fastq.sorted.bam"
test -f "$tmp/reference-out/qc/multiqc_report.html"
test -f "$tmp/reference-out/variants/toy_fastq.normalized.vcf.gz"
test -f "$tmp/reference-out/report/report_index.html"
test -f "$tmp/reference-out/report/findings.tsv"
test -f "$tmp/reference-out/report/evidence.json"
grep -q 'Coverage summary generated' "$tmp/reference-out/report/findings.tsv"

clair3_cache="$repo/.tools/clair3-smoke"
clair3_model="$clair3_cache/model/hifi"
clair3_data="$clair3_cache/pacbio_hifi"
mkdir -p "$clair3_model" "$clair3_data"
for file in pileup.pt full_alignment.pt; do
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/clair3_models_pytorch/hifi/$file" "$clair3_model/$file"
done
for file in GRCh38_no_alt_chr20.fa GRCh38_no_alt_chr20.fa.fai HG003_chr20_demo.bam HG003_chr20_demo.bam.bai; do
	download_if_missing "http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/pacbio_hifi/$file" "$clair3_data/$file"
done
printf 'chr20\t100000\t300000\n' >"$tmp/clair3.quick_demo.bed"
PATH="$opengenome_bin:$PATH" gatk CreateSequenceDictionary \
	-R "$clair3_data/GRCh38_no_alt_chr20.fa" \
	-O "$tmp/GRCh38_no_alt_chr20.dict" >/dev/null
printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/clair3_samples.csv"
printf 'HG003,HG003_hifi,lane_1,alignment,,,%s,,,,,NA,0\n' "$clair3_data/HG003_chr20_demo.bam" >>"$tmp/clair3_samples.csv"

PATH="$opengenome_bin:$PATH" nextflow -log "$tmp/clair3.nextflow.log" run core/tabs/open-genome/pipelines/open-genome \
	-profile opengenome \
	--input_dir "$clair3_data" \
	--samplesheet "$tmp/clair3_samples.csv" \
	--outdir "$tmp/clair3-out" \
	--max_cpus 2 \
	--fasta "$clair3_data/GRCh38_no_alt_chr20.fa" \
	--fasta_fai "$clair3_data/GRCh38_no_alt_chr20.fa.fai" \
	--dict "$tmp/GRCh38_no_alt_chr20.dict" \
	--sequencing_platform pacbio_hifi \
	--variant_caller clair3 \
	--clair3_model "$clair3_model" \
	--clair3_platform hifi \
	--clair3_bed "$tmp/clair3.quick_demo.bed" \
	--clair3_ctg chr20 \
	--clair3_chunk_size 100000000 \
	-w "$tmp/clair3-work"

test -s "$tmp/clair3-out/variants/HG003_hifi.clair3.vcf.gz"
test -s "$tmp/clair3-out/variants/HG003_hifi.clair3.vcf.gz.tbi"
test -s "$tmp/clair3-out/variants/HG003_hifi.normalized.vcf.gz"
test -f "$tmp/clair3-out/report/report_index.html"
PATH="$opengenome_bin:$PATH" bcftools view -H "$tmp/clair3-out/variants/HG003_hifi.clair3.vcf.gz" | head -1 | grep -q '^chr20'

clair3_ont_model="$clair3_cache/model/r1041_e82_400bps_sup_v500"
clair3_ont_data="$clair3_cache/ont"
mkdir -p "$clair3_ont_model" "$clair3_ont_data"
for file in pileup.pt full_alignment.pt; do
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/clair3_models_pytorch/r1041_e82_400bps_sup_v500/$file" "$clair3_ont_model/$file"
done
for file in GRCh38_no_alt_chr20.fa GRCh38_no_alt_chr20.fa.fai HG003_chr20_demo.bam HG003_chr20_demo.bam.bai; do
	download_if_missing "http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/ont/$file" "$clair3_ont_data/$file"
done
printf 'chr20\t100000\t300000\n' >"$tmp/clair3.ont.quick_demo.bed"
PATH="$opengenome_bin:$PATH" gatk CreateSequenceDictionary \
	-R "$clair3_ont_data/GRCh38_no_alt_chr20.fa" \
	-O "$tmp/GRCh38_no_alt_chr20_ont.dict" >/dev/null
printf 'sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\n' >"$tmp/clair3_ont_samples.csv"
printf 'HG003,HG003_ont,lane_1,alignment,,,%s,,,,,NA,0\n' "$clair3_ont_data/HG003_chr20_demo.bam" >>"$tmp/clair3_ont_samples.csv"

PATH="$opengenome_bin:$PATH" nextflow -log "$tmp/clair3-ont.nextflow.log" run core/tabs/open-genome/pipelines/open-genome \
	-profile opengenome \
	--input_dir "$clair3_ont_data" \
	--samplesheet "$tmp/clair3_ont_samples.csv" \
	--outdir "$tmp/clair3-ont-out" \
	--max_cpus 2 \
	--fasta "$clair3_ont_data/GRCh38_no_alt_chr20.fa" \
	--fasta_fai "$clair3_ont_data/GRCh38_no_alt_chr20.fa.fai" \
	--dict "$tmp/GRCh38_no_alt_chr20_ont.dict" \
	--sequencing_platform ont \
	--variant_caller clair3 \
	--clair3_model "$clair3_ont_model" \
	--clair3_platform ont \
	--clair3_bed "$tmp/clair3.ont.quick_demo.bed" \
	--clair3_ctg chr20 \
	--clair3_chunk_size 100000000 \
	-w "$tmp/clair3-ont-work"

test -s "$tmp/clair3-ont-out/variants/HG003_ont.clair3.vcf.gz"
test -s "$tmp/clair3-ont-out/variants/HG003_ont.clair3.vcf.gz.tbi"
test -s "$tmp/clair3-ont-out/variants/HG003_ont.normalized.vcf.gz"
test -f "$tmp/clair3-ont-out/report/report_index.html"
PATH="$opengenome_bin:$PATH" bcftools view -H "$tmp/clair3-ont-out/variants/HG003_ont.clair3.vcf.gz" | head -1 | grep -q '^chr20'

if test -n "$denovo_bin" && test -x "$denovo_bin/nextflow" &&
	PATH="$denovo_bin:$PATH" bash -c 'for tool in nextflow flye hifiasm gfastats seqkit pigz minimap2; do command -v "$tool" >/dev/null || exit 1; done'; then
	denovo_prefix=${denovo_bin%/bin}
	denovo_flye_reads=$(find "$denovo_prefix/lib" -path '*/site-packages/flye/tests/data/ecoli_500kb_reads.fastq.gz' -print -quit)
	denovo_hifi_reads=$(find "$denovo_prefix/lib" -path '*/site-packages/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz' -print -quit)
	if test -n "$denovo_flye_reads" && test -s "$denovo_flye_reads" && test -n "$denovo_hifi_reads" && test -s "$denovo_hifi_reads"; then
		PATH="$denovo_bin:$PATH" flye \
			--pacbio-raw "$denovo_flye_reads" \
			--out-dir "$tmp/flye-direct" \
			--threads 2 \
			--genome-size 500k \
			--stop-after assembly \
			>"$tmp/flye-direct.log" 2>&1
		test -s "$tmp/flye-direct/00-assembly/draft_assembly.fasta"
		PATH="$denovo_bin:$PATH" gfastats "$tmp/flye-direct/00-assembly/draft_assembly.fasta" >"$tmp/flye-direct.gfastats.txt"
		test -s "$tmp/flye-direct.gfastats.txt"

		python3 - "$tmp/hifiasm_samples.csv" "$denovo_hifi_reads" <<'PY'
import csv
import sys

header = [
    "sample",
    "row_id",
    "lane",
    "input_type",
    "fastq_1",
    "fastq_2",
    "bam",
    "cram",
    "vcf",
    "assembly",
    "long_reads",
    "sex",
    "status",
]
row = {key: "" for key in header}
row.update(
    sample="ecoli",
    row_id="ecoli_hifiasm",
    lane="lane_1",
    input_type="long_reads",
    long_reads=sys.argv[2],
    sex="NA",
    status="0",
)
with open(sys.argv[1], "w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=header)
    writer.writeheader()
    writer.writerow(row)
PY

		PATH="$denovo_bin:$PATH" nextflow -log "$tmp/hifiasm.nextflow.log" run core/tabs/open-genome/pipelines/denovo-assembly \
			-profile opengenome \
			--samplesheet "$tmp/hifiasm_samples.csv" \
			--input_dir "$(dirname "$denovo_hifi_reads")" \
			--outdir "$tmp/hifiasm-out" \
			--max_cpus 2 \
			--assembler_threads 2 \
			--assembler hifiasm \
			--long_read_platform hifi \
			--genome_size 500k \
			-w "$tmp/hifiasm-work"

		test -s "$tmp/hifiasm-out/assembly/ecoli_hifiasm.primary.fasta"
		test -s "$tmp/hifiasm-out/assembly/ecoli_hifiasm.primary.gfa"
		test -s "$tmp/hifiasm-out/assembly/ecoli_hifiasm.hifiasm.log"
		test -s "$tmp/hifiasm-out/report/denovo_assembly_report.html"
		test -s "$tmp/hifiasm-out/report/denovo_assembly_summary.tsv"
		test -s "$tmp/hifiasm-out/report/denovo_assembly_manifest.json"
		awk -F '\t' 'NR == 2 { exit !($2 == "hifiasm" && $3 == "hifi" && $4 + 0 > 0 && $5 + 0 > 300000) }' "$tmp/hifiasm-out/report/denovo_assembly_summary.tsv"
	else
		echo "== Real de novo smoke skipped: Flye E. coli test fixture not found =="
	fi
else
	echo "== Real de novo smoke skipped: opengenome-denovo environment is not installed or is missing tools =="
fi

echo "ok - real Nextflow smoke"
