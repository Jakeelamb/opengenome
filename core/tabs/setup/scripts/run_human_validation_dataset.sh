#!/usr/bin/env bash
set -euo pipefail

_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest >/dev/null

workdir=$(open_genome_workdir)
cache_root=$(open_genome_manifest_get cache.root)
if test -z "$cache_root"; then
	cache_root=$(open_genome_cache_dir)
	open_genome_manifest_set cache.root "$cache_root"
fi

target_coverage=${OPEN_GENOME_HUMAN_VALIDATION_TARGET_COVERAGE:-10}
force=${OPEN_GENOME_RERUN_HUMAN_VALIDATION:-0}
test_mode=${OPEN_GENOME_HUMAN_VALIDATION_TEST_MODE:-0}

data_root=$cache_root/human-validation/hg003-hifi-chr20
model_root=$cache_root/clair3-models/hifi
outdir=$workdir/open-genome-human-validation-results
input_dir=$workdir/human-validation-inputs/hg003-hifi-chr20-${target_coverage}x
reference_out=$outdir/reference-germline
vcf_out=$outdir/existing-vcf
denovo_out=$outdir/denovo-assembly
index_report_dir=$outdir/report

reference=$data_root/GRCh38_no_alt_chr20.fa
source_bam=$data_root/HG003_chr20_demo.bam
downsampled_bam=$input_dir/HG003_hifi_${target_coverage}x.bam
long_reads=$input_dir/HG003_hifi_${target_coverage}x.fastq.gz
region_bed=$input_dir/HG003_chr20_100000_300000.bed
dict=$input_dir/GRCh38_no_alt_chr20.dict
reference_samplesheet=$input_dir/reference_samplesheet.csv
vcf_samplesheet=$input_dir/vcf_samplesheet.csv
denovo_samplesheet=$input_dir/denovo_samplesheet.csv

complete_outputs() {
	test -s "$reference_out/report/report_index.html" &&
		test -s "$vcf_out/report/report_index.html" &&
		test -s "$denovo_out/report/denovo_assembly_report.html"
}

download_if_missing() {
	url=$1
	dest=$2
	if test -s "$dest"; then
		return 0
	fi
	mkdir -p "$(dirname "$dest")"
	echo "Downloading: $url"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 --retry-delay 2 -o "$dest.tmp" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$dest.tmp" "$url"
	else
		echo "curl or wget is required to download the human validation dataset." >&2
		exit 1
	fi
	test -s "$dest.tmp"
	mv "$dest.tmp" "$dest"
}

record_outputs() {
	mkdir -p "$index_report_dir"
	if test -s "$reference_out/report/findings.tsv"; then
		cp "$reference_out/report/findings.tsv" "$index_report_dir/findings.tsv"
	fi
	if test -s "$reference_out/report/evidence.json"; then
		cp "$reference_out/report/evidence.json" "$index_report_dir/evidence.json"
	fi
	if test -s "$reference_out/report/run_manifest.json"; then
		cp "$reference_out/report/run_manifest.json" "$index_report_dir/run_manifest.json"
	fi
	cat >"$index_report_dir/report_index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome Human Validation Results</title>
  <style>
    :root { color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #f6f8fb; color: #1c2024; }
    main { max-width: 1080px; margin: 0 auto; padding: 34px 20px 48px; }
    h1 { margin: 0 0 10px; font-size: clamp(2rem, 5vw, 3rem); }
    p { line-height: 1.55; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(245px, 1fr)); gap: 14px; margin-top: 24px; }
    a.card { display: block; padding: 18px; border: 1px solid #d9dee7; border-radius: 8px; background: white; color: inherit; text-decoration: none; }
    a.card strong { display: block; margin-bottom: 8px; font-size: 1.05rem; }
    .files { margin-top: 26px; padding: 18px; border-left: 4px solid #2b6cb0; background: #edf5ff; }
    code { word-break: break-all; }
    @media (prefers-color-scheme: dark) {
      body { background: #111417; color: #eef1f5; }
      a.card { background: #171b20; border-color: #2d3642; }
      .files { background: #162433; }
    }
  </style>
</head>
<body>
  <main>
    <h1>Open Genome Human Validation Results</h1>
    <p>These outputs were generated from public GIAB HG003 PacBio HiFi reads over GRCh38 chr20:100000-300000, downsampled to approximately ${target_coverage}x coverage. The folders are kept on disk so Results -> Open my report and Results -> Explain my results can reload them without recomputing.</p>
    <div class="grid">
      <a class="card" href="../reference-germline/report/report_index.html"><strong>Reference germline pipeline</strong>Human alignment through QC, Clair3 variant calling, normalization, annotation summaries, and native report output.</a>
      <a class="card" href="../existing-vcf/report/report_index.html"><strong>Existing VCF pipeline</strong>The generated human VCF reloaded through the existing-VCF report pipeline.</a>
      <a class="card" href="../denovo-assembly/report/denovo_assembly_report.html"><strong>De novo assembly pipeline</strong>The same downsampled human reads passed through the long-read assembly report path.</a>
    </div>
    <section class="files">
      <p><strong>Results folder:</strong> <code>$outdir</code></p>
      <p><strong>Input folder:</strong> <code>$input_dir</code></p>
      <p><strong>Source data cache:</strong> <code>$data_root</code></p>
    </section>
  </main>
</body>
</html>
EOF

	open_genome_paths_set workdir "$workdir"
	open_genome_paths_set dataset "$input_dir"
	open_genome_manifest_set reference.fasta "$reference"
	open_genome_manifest_set reference.fai "$reference.fai"
	open_genome_manifest_set reference.dict "$dict"
	open_genome_manifest_set sample.samplesheet "$reference_samplesheet"
	open_genome_manifest_set sample.input_dir "$input_dir"
	open_genome_manifest_set sample.input_type "human_validation"
	open_genome_manifest_set sample.recommended_plan "Human validation: HG003 HiFi chr20 ${target_coverage}x through reference, existing VCF, and de novo pipelines"
	open_genome_manifest_set workflow.outdir "$outdir"
	open_genome_manifest_set workflow.recommended_plan "Human validation: HG003 HiFi chr20 ${target_coverage}x through reference, existing VCF, and de novo pipelines"
	open_genome_manifest_set results.report_dir "$index_report_dir"
	open_genome_manifest_set results.report_html "$index_report_dir/report_index.html"
	open_genome_manifest_set results.findings_tsv "$index_report_dir/findings.tsv"
	open_genome_manifest_set results.evidence_json "$index_report_dir/evidence.json"
	open_genome_manifest_set results.denovo_report_dir "$denovo_out/report"
	open_genome_manifest_set results.denovo_report_html "$denovo_out/report/denovo_assembly_report.html"
	open_genome_manifest_set results.denovo_summary_tsv "$denovo_out/report/denovo_assembly_summary.tsv"
	open_genome_manifest_set results.denovo_manifest_json "$denovo_out/report/denovo_assembly_manifest.json"
}

if test "$force" != "1" && complete_outputs; then
	record_outputs
	echo "Loaded existing human validation results:"
	echo ""
	echo "  Results folder:            $outdir"
	echo "  Preview index:             $index_report_dir/report_index.html"
	echo "  Reference germline report: $reference_out/report/report_index.html"
	echo "  Existing VCF report:       $vcf_out/report/report_index.html"
	echo "  De novo assembly report:   $denovo_out/report/denovo_assembly_report.html"
	echo ""
	echo "Set OPEN_GENOME_RERUN_HUMAN_VALIDATION=1 to regenerate them."
	exit 0
fi

echo "Run public human validation data through Open Genome"
echo ""
echo "Dataset: GIAB HG003 PacBio HiFi chr20:100000-300000"
echo "Target coverage: ${target_coverage}x"
echo "Outputs stay local and are reused on the next run."
echo ""

mkdir -p "$data_root" "$model_root" "$input_dir" "$outdir"

if test "$test_mode" = "1"; then
	opengenome_path=$PATH
	denovo_path=$PATH
	printf '>chr20\nACGTACGTACGTACGTACGTACGTACGTACGT\n' >"$reference"
	printf 'chr20\t32\t7\t32\t33\n' >"$reference.fai"
	printf '@HD\tVN:1.6\n@SQ\tSN:chr20\tLN:32\n' >"$dict"
	touch "$downsampled_bam" "$downsampled_bam.bai" "$long_reads" "$model_root/pileup.pt" "$model_root/full_alignment.pt"
	printf 'chr20\t100000\t300000\n' >"$region_bed"
else
	open_genome_resolve_conda
	opengenome_prefix=$("$OG_CONDA_EXE" env list 2>/dev/null | awk '$1 == "opengenome" { print $NF; exit }')
	denovo_prefix=$("$OG_CONDA_EXE" env list 2>/dev/null | awk '$1 == "opengenome-denovo" { print $NF; exit }')
	if test -z "$opengenome_prefix" || ! test -x "$opengenome_prefix/bin/nextflow"; then
		echo "The opengenome conda environment is required. Run Start Here -> Advanced manual setup -> Install or update local tools." >&2
		exit 1
	fi
	if test -z "$denovo_prefix" || ! test -x "$denovo_prefix/bin/nextflow"; then
		echo "The opengenome-denovo conda environment is required. Run Start Here -> Advanced manual setup -> Install or update local tools." >&2
		exit 1
	fi
	if ! PATH="$opengenome_prefix/bin:$PATH" bash -c 'for tool in nextflow samtools gatk bcftools bgzip tabix curl; do command -v "$tool" >/dev/null || exit 1; done'; then
		echo "The opengenome environment is missing required human-validation tools." >&2
		exit 1
	fi
	if ! PATH="$denovo_prefix/bin:$PATH" bash -c 'for tool in nextflow hifiasm gfastats seqkit samtools pigz minimap2; do command -v "$tool" >/dev/null || exit 1; done'; then
		echo "The opengenome-denovo environment is missing required human-validation tools." >&2
		exit 1
	fi
	opengenome_path="$opengenome_prefix/bin:$(dirname "$OG_CONDA_EXE"):$PATH"
	denovo_path="$denovo_prefix/bin:$(dirname "$OG_CONDA_EXE"):$PATH"

	download_if_missing "https://www.bio8.cs.hku.hk/clair3/demo/quick_demo/pacbio_hifi/GRCh38_no_alt_chr20.fa" "$reference"
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/demo/quick_demo/pacbio_hifi/GRCh38_no_alt_chr20.fa.fai" "$reference.fai"
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/demo/quick_demo/pacbio_hifi/HG003_chr20_demo.bam" "$source_bam"
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/demo/quick_demo/pacbio_hifi/HG003_chr20_demo.bam.bai" "$source_bam.bai"
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/clair3_models_pytorch/hifi/pileup.pt" "$model_root/pileup.pt"
	download_if_missing "https://www.bio8.cs.hku.hk/clair3/clair3_models_pytorch/hifi/full_alignment.pt" "$model_root/full_alignment.pt"

	printf 'chr20\t100000\t300000\n' >"$region_bed"
	PATH="$opengenome_path" gatk CreateSequenceDictionary -R "$reference" -O "$dict" >/dev/null

	observed_coverage=$(PATH="$opengenome_path" samtools depth -r chr20:100000-300000 "$source_bam" | awk 'BEGIN { bases=200001; sum=0 } { sum += $3 } END { if (bases > 0) printf "%.4f", sum / bases; else print "0" }')
	sampling_fraction=$(python3 - "$target_coverage" "$observed_coverage" <<'PY'
import sys

target = float(sys.argv[1])
observed = float(sys.argv[2])
fraction = 1.0 if observed <= 0 else min(1.0, target / observed)
print(f"{fraction:.6f}")
PY
)
	echo "Observed source coverage over chr20:100000-300000: ${observed_coverage}x"
	if python3 - "$sampling_fraction" <<'PY'
import sys
raise SystemExit(0 if float(sys.argv[1]) >= 0.999999 else 1)
PY
	then
		echo "Target coverage is at or above source coverage; copying the bounded region."
		PATH="$opengenome_path" samtools view -@ 2 -b "$source_bam" chr20:100000-300000 >"$downsampled_bam"
	else
		sampling_arg=$(python3 - "$sampling_fraction" <<'PY'
import sys
fraction = float(sys.argv[1])
print(f"23.{int(round(fraction * 1_000_000)):06d}")
PY
)
		echo "Downsampling with samtools view -s ${sampling_arg}"
		PATH="$opengenome_path" samtools view -@ 2 -b -s "$sampling_arg" "$source_bam" chr20:100000-300000 >"$downsampled_bam"
	fi
	PATH="$opengenome_path" samtools index "$downsampled_bam"
	PATH="$opengenome_path" samtools fastq -@ 2 "$downsampled_bam" | PATH="$denovo_path" pigz -p 2 >"$long_reads"
fi

cat >"$reference_samplesheet" <<EOF
sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status
HG003,HG003_hifi_${target_coverage}x,lane_1,alignment,,,$downsampled_bam,,,,,NA,0
EOF
cat >"$denovo_samplesheet" <<EOF
sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status
HG003,HG003_hifi_${target_coverage}x_denovo,lane_1,long_reads,,,,,,,$long_reads,NA,0
EOF

run_nextflow() {
	local path_prefix=$1
	local log=$2
	shift 2
	PATH="$path_prefix" NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}" nextflow -log "$log" run "$@"
}

echo "Running human reference germline pipeline..."
run_nextflow "$opengenome_path" "$outdir/reference.nextflow.log" "$OPEN_GENOME_BUNDLE/pipelines/open-genome" \
	-profile opengenome \
	--input_dir "$input_dir" \
	--samplesheet "$reference_samplesheet" \
	--outdir "$reference_out" \
	--max_cpus 2 \
	--fasta "$reference" \
	--fasta_fai "$reference.fai" \
	--dict "$dict" \
	--sequencing_platform pacbio_hifi \
	--variant_caller clair3 \
	--clair3_model "$model_root" \
	--clair3_platform hifi \
	--clair3_bed "$region_bed" \
	--clair3_ctg chr20 \
	--clair3_chunk_size 100000000 \
	-w "$outdir/.work/reference"

human_vcf=$reference_out/variants/HG003_hifi_${target_coverage}x.normalized.vcf.gz
if ! test -s "$human_vcf"; then
	echo "Reference pipeline did not produce expected VCF: $human_vcf" >&2
	exit 1
fi

cat >"$vcf_samplesheet" <<EOF
sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status
HG003,HG003_hifi_${target_coverage}x_vcf,lane_1,vcf,,,,,$human_vcf,,,NA,0
EOF

echo "Running human existing-VCF pipeline..."
run_nextflow "$opengenome_path" "$outdir/vcf.nextflow.log" "$OPEN_GENOME_BUNDLE/pipelines/vcf-annotate" \
	-profile opengenome \
	--input_dir "$input_dir" \
	--samplesheet "$vcf_samplesheet" \
	--outdir "$vcf_out" \
	--max_cpus 2 \
	--fasta "$reference" \
	-w "$outdir/.work/vcf"

echo "Running human de novo assembly pipeline..."
run_nextflow "$denovo_path" "$outdir/denovo.nextflow.log" "$OPEN_GENOME_BUNDLE/pipelines/denovo-assembly" \
	-profile opengenome \
	--input_dir "$input_dir" \
	--samplesheet "$denovo_samplesheet" \
	--outdir "$denovo_out" \
	--max_cpus 2 \
	--assembler_threads 2 \
	--assembler hifiasm \
	--long_read_platform hifi \
	--genome_size 200k \
	-w "$outdir/.work/denovo"

test -s "$reference_out/report/report_index.html"
test -s "$vcf_out/report/report_index.html"
test -s "$denovo_out/report/denovo_assembly_report.html"

record_outputs

echo ""
echo "Human validation outputs generated and loaded:"
echo ""
echo "  Results folder:            $outdir"
echo "  Input folder:              $input_dir"
echo "  Preview index:             $index_report_dir/report_index.html"
echo "  Reference germline report: $reference_out/report/report_index.html"
echo "  Existing VCF report:       $vcf_out/report/report_index.html"
echo "  De novo assembly report:   $denovo_out/report/denovo_assembly_report.html"
echo ""
echo "Next: Results -> Open my report, or Results -> Explain my results."
