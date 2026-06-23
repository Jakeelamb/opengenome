#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest >/dev/null

workdir=$(open_genome_workdir)
demo_root=$workdir/demo
dataset_dir=$demo_root/sequencing
reference_dir=$demo_root/reference
samples_dir=$demo_root/samples
outdir=$workdir/open-genome-results

reference_out=$outdir/reference-germline
existing_vcf_out=$outdir/existing-vcf
denovo_out=$outdir/denovo-assembly
index_report_dir=$outdir/report

sample_id=OpenGenome_demo_HG002
reference_row=OpenGenome_demo_HG002_illumina
vcf_row=OpenGenome_demo_HG002_vcf
denovo_row=OpenGenome_demo_HG002_hifi

vcf=$dataset_dir/$sample_id.vcf.gz
reference=$reference_dir/tiny_grch38_smoke.fa
reference_samplesheet=$samples_dir/reference_germline_samplesheet.csv
vcf_samplesheet=$samples_dir/existing_vcf_samplesheet.csv
denovo_samplesheet=$samples_dir/denovo_assembly_samplesheet.csv

echo "Preview bundled Open Genome outputs"
echo ""
echo "This creates tiny local demo results for the reference germline, existing VCF, and de novo assembly workflows."
echo "No files are downloaded, uploaded, or analyzed with heavy tools."
echo ""

mkdir -p "$dataset_dir" "$reference_dir" "$samples_dir" "$reference_out" "$existing_vcf_out" "$denovo_out" "$index_report_dir"

cat >"$reference" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
>chrM
ACGTACGTACGTACGTACGT
EOF
cat >"$reference.fai" <<'EOF'
chr1	40	6	40	41
chrM	20	53	20	21
EOF
cat >"$reference_dir/tiny_grch38_smoke.dict" <<'EOF'
@HD	VN:1.6
@SQ	SN:chr1	LN:40
@SQ	SN:chrM	LN:20
EOF

cat >"$dataset_dir/$sample_id.R1.fastq" <<'EOF'
@OpenGenome_demo_HG002/1
ACGTACGTACGTACGTACGT
+
IIIIIIIIIIIIIIIIIIII
EOF
cat >"$dataset_dir/$sample_id.R2.fastq" <<'EOF'
@OpenGenome_demo_HG002/2
TGCATGCATGCATGCATGCA
+
IIIIIIIIIIIIIIIIIIII
EOF
gzip -f "$dataset_dir/$sample_id.R1.fastq"
gzip -f "$dataset_dir/$sample_id.R2.fastq"

cat >"$dataset_dir/$sample_id.hifi.fastq" <<'EOF'
@OpenGenome_demo_HG002_hifi
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
EOF
gzip -f "$dataset_dir/$sample_id.hifi.fastq"

tmp_vcf=$demo_root/$sample_id.vcf
cat >"$tmp_vcf" <<'EOF'
##fileformat=VCFv4.2
##contig=<ID=chr1,length=40>
##contig=<ID=chrM,length=20>
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	OpenGenome_demo_HG002
chr1	10	rs-demo-1	A	G	60	PASS	ANN=G|missense_variant|MODERATE|GENE1|GENE1|transcript|TX1|protein_coding|1/1|c.10A>G|p.Lys4Arg|10/30|10/30|4/10||	GT	0/1
chr1	20	rs-demo-2	C	CT	60	PASS	ANN=CT|frameshift_variant|HIGH|GENE2|GENE2|transcript|TX2|protein_coding|1/1|c.20dupT|p.Gly7fs|20/30|20/30|7/10||	GT	0/1
chrM	5	mt-demo-1	A	T	60	PASS	.	GT	0/1
EOF
gzip -c "$tmp_vcf" >"$vcf"
rm -f "$tmp_vcf"

cat >"$reference_samplesheet" <<EOF
sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status
$sample_id,$reference_row,lane_1,fastq,$dataset_dir/$sample_id.R1.fastq.gz,$dataset_dir/$sample_id.R2.fastq.gz,,,,,,NA,0
EOF
cat >"$vcf_samplesheet" <<EOF
sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status
$sample_id,$vcf_row,lane_1,vcf,,,,,$vcf,,,NA,0
EOF
cat >"$denovo_samplesheet" <<EOF
sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status
$sample_id,$denovo_row,lane_1,long_reads,,,,,,,$dataset_dir/$sample_id.hifi.fastq.gz,NA,0
EOF

write_report_inputs() {
	row_id=$1
	sample=$2
	inputs=$3
	mkdir -p "$inputs"
	cat >"$inputs/$row_id.variant_summary.tsv" <<EOF
chrom	pos	id	ref	alt	gt
chr1	10	rs-demo-1	A	G	0/1
chr1	20	rs-demo-2	C	CT	0/1
chrM	5	mt-demo-1	A	T	0/1
EOF
	cat >"$inputs/$row_id.clinvar.matches.tsv" <<EOF
chrom	pos	id	ref	alt	gt
chr1	20	rs-demo-2	C	CT	0/1
EOF
	cat >"$inputs/$row_id.public_annotations.tsv" <<EOF
row_id	sample	chrom	pos	id	ref	alt	source	label	value	note
$row_id	$sample	chr1	10	rs-demo-1	A	G	dbSNP	variant ID	rs-demo-1	Toy public identifier for local preview
$row_id	$sample	chr1	20	rs-demo-2	C	CT	gnomAD	frequency	0.001	Toy frequency for local preview
EOF
	cat >"$inputs/$row_id.consequence_summary.tsv" <<EOF
row_id	sample	tool	state	consequence	gene	impact	count	note
$row_id	$sample	SnpEff ANN	parsed	missense_variant	GENE1	MODERATE	1	Demo annotation parsed from the toy VCF
$row_id	$sample	SnpEff ANN	parsed	frameshift_variant	GENE2	HIGH	1	Demo annotation parsed from the toy VCF
EOF
	cat >"$inputs/$row_id.mosdepth.summary.txt" <<'EOF'
chrom	length	bases	mean	min	max
chr1	40	1200	30	12	42
chrM	20	3600	180	120	220
total	60	4800	80	12	220
EOF
	printf 'chr1\t0\t40\tchr1\t40\t40\t38\t35\nchrM\t0\t20\tchrM\t20\t20\t20\t20\n' | gzip -c >"$inputs/$row_id.thresholds.bed.gz"
	cat >"$inputs/$row_id.mitochondrial_status.tsv" <<EOF
row_id	sample	state	message
$row_id	$sample	complete	Demo chrM coverage and variants were summarized
EOF
	cat >"$inputs/$row_id.mitochondrial_consensus.fa" <<'EOF'
>chrM
ACGTACGTACGTACGTACGT
EOF
	cat >"$inputs/$row_id.pharmcat_status.tsv" <<EOF
row_id	sample	step	state	message
$row_id	$sample	pharmcat	skipped	PharmCAT is not needed for the local preview
EOF
	cat >"$inputs/$row_id.gfastats.txt" <<'EOF'
total length: 60
number of scaffolds: 2
N50: 40
N90: 20
auN: 33.33
EOF
	cat >"$inputs/multiqc_report.html" <<'EOF'
<!doctype html><html><body><h1>Open Genome demo MultiQC placeholder</h1></body></html>
EOF
}

publish_variant_outputs() {
	row_id=$1
	sample=$2
	workflow_out=$3
	samplesheet=$4
	input_type=$5

	report_inputs=$demo_root/report-inputs/$input_type
	write_report_inputs "$row_id" "$sample" "$report_inputs"

	mkdir -p "$workflow_out/qc" "$workflow_out/alignment" "$workflow_out/variants" "$workflow_out/annotations" "$workflow_out/mitochondrial" "$workflow_out/report" "$workflow_out/pipeline_info"
	cp "$report_inputs/multiqc_report.html" "$workflow_out/qc/multiqc_report.html"
	cp "$report_inputs/$row_id.mosdepth.summary.txt" "$workflow_out/qc/$row_id.mosdepth.summary.txt"
	cp "$report_inputs/$row_id.thresholds.bed.gz" "$workflow_out/qc/$row_id.thresholds.bed.gz"
	cp "$report_inputs/$row_id.variant_summary.tsv" "$workflow_out/annotations/$row_id.variant_summary.tsv"
	cp "$report_inputs/$row_id.clinvar.matches.tsv" "$workflow_out/annotations/$row_id.clinvar.matches.tsv"
	cp "$report_inputs/$row_id.public_annotations.tsv" "$workflow_out/annotations/$row_id.public_annotations.tsv"
	cp "$report_inputs/$row_id.consequence_summary.tsv" "$workflow_out/annotations/$row_id.consequence_summary.tsv"
	cp "$report_inputs/$row_id.pharmcat_status.tsv" "$workflow_out/annotations/$row_id.pharmcat_status.tsv"
	cp "$report_inputs/$row_id.mitochondrial_status.tsv" "$workflow_out/mitochondrial/$row_id.mitochondrial_status.tsv"
	cp "$report_inputs/$row_id.mitochondrial_consensus.fa" "$workflow_out/mitochondrial/$row_id.mitochondrial_consensus.fa"
	cp "$vcf" "$workflow_out/variants/$row_id.normalized.vcf.gz"
	cp "$vcf" "$workflow_out/annotations/$row_id.annotated.vcf.gz"
	touch "$workflow_out/variants/$row_id.normalized.vcf.gz.tbi"
	cat >"$workflow_out/variants/$row_id.bcftools.stats.txt" <<'EOF'
SN	number of records:	3
EOF
	cat >"$workflow_out/pipeline_info/execution_report.html" <<EOF
<!doctype html><html><body><h1>$input_type preview pipeline info</h1></body></html>
EOF

	if test "$input_type" = "reference-germline"; then
		touch "$workflow_out/alignment/$row_id.sorted.bam" "$workflow_out/alignment/$row_id.sorted.bam.bai"
		cat >"$workflow_out/qc/fastp.$row_id.json" <<EOF
{
  "summary": {
    "before_filtering": {
      "total_reads": 2,
      "total_bases": 40,
      "q30_rate": 0.98
    },
    "after_filtering": {
      "total_reads": 2,
      "total_bases": 40,
      "q30_rate": 0.99
    }
  }
}
EOF
		cat >"$workflow_out/qc/fastp.$row_id.html" <<EOF
<!doctype html><html><body><h1>fastp preview for $row_id</h1><p>Reads before filtering: 2</p><p>Reads after filtering: 2</p><p>Q30 after filtering: 99%</p></body></html>
EOF
		cat >"$workflow_out/qc/$row_id.trimmed.R1_fastqc.html" <<EOF
<!doctype html><html><body><h1>FastQC R1 preview for $row_id</h1><p>Per-base quality: pass</p><p>Adapter content: pass</p></body></html>
EOF
		cat >"$workflow_out/qc/$row_id.trimmed.R2_fastqc.html" <<EOF
<!doctype html><html><body><h1>FastQC R2 preview for $row_id</h1><p>Per-base quality: pass</p><p>Adapter content: pass</p></body></html>
EOF
		cat >"$workflow_out/qc/$row_id.read_density.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="220" viewBox="0 0 760 220" role="img" aria-label="Read density preview">
  <rect width="760" height="220" fill="#fbfcfc"/>
  <text x="24" y="32" font-family="sans-serif" font-size="18" fill="#172026">Read density across tiny reference</text>
  <line x1="60" y1="180" x2="720" y2="180" stroke="#8a98a3"/>
  <line x1="60" y1="52" x2="60" y2="180" stroke="#8a98a3"/>
  <text x="60" y="205" font-family="sans-serif" font-size="12" fill="#5d6a72">chr1</text>
  <text x="520" y="205" font-family="sans-serif" font-size="12" fill="#5d6a72">chrM</text>
  <polyline fill="none" stroke="#196b69" stroke-width="4" points="60,145 130,122 200,105 270,118 340,92 410,110 480,86 550,70 620,74 690,64"/>
  <circle cx="340" cy="92" r="5" fill="#7a4f12"/>
  <text x="70" y="64" font-family="sans-serif" font-size="12" fill="#5d6a72">mean depth</text>
</svg>
EOF
		cat >"$workflow_out/qc/$row_id.samtools.flagstat.txt" <<'EOF'
6 + 0 in total
EOF
	else
		cat >"$workflow_out/variants/$row_id.vcf_ingress_status.tsv" <<EOF
row_id	sample	step	state	message
$row_id	$sample	normalize	complete	Existing VCF normalized with bcftools
EOF
	fi

	python3 "$OPEN_GENOME_BUNDLE/lib/report_compiler.py" \
		--input-dir "$workflow_out" \
		--out-dir "$workflow_out/report" \
		--samplesheet "$samplesheet" \
		--reference "$reference"
}

publish_denovo_outputs() {
	mkdir -p "$denovo_out/reads" "$denovo_out/qc" "$denovo_out/assembly" "$denovo_out/report" "$denovo_out/pipeline_info"
	cp "$dataset_dir/$sample_id.hifi.fastq.gz" "$denovo_out/reads/$denovo_row.reads.fastq.gz"
	cat >"$denovo_out/qc/$denovo_row.seqkit_stats.tsv" <<EOF
file	format	type	num_seqs	sum_len	min_len	avg_len	max_len
$denovo_row.reads.fastq.gz	FASTQ	DNA	1	48	48	48.0	48
EOF
	cat >"$denovo_out/assembly/$denovo_row.primary.fasta" <<'EOF'
>contig_1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
>contig_2
ACGTACGTACGTACGTACGT
EOF
	cat >"$denovo_out/assembly/$denovo_row.primary.gfa" <<'EOF'
S	contig_1	ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
S	contig_2	ACGTACGTACGTACGTACGT
EOF
	cat >"$denovo_out/assembly/$denovo_row.hifiasm.log" <<EOF
hifiasm preview run for $denovo_row
EOF
	cat >"$denovo_out/assembly/$denovo_row.gfastats.txt" <<'EOF'
scaffold count: 2
total scaffold length: 60
scaffold N50: 40
longest scaffold: 40
EOF
	cat >"$denovo_out/assembly/$denovo_row.circularity.tsv" <<EOF
row_id	contig	length	circularity	terminal_overlap_bp	evidence	note
$denovo_row	contig_1	40	likely_circular	12	matching terminal sequence	Toy preview signal for circular contig review
$denovo_row	contig_2	20	linear	0	no terminal overlap	Short secondary contig remains linear in preview
EOF
	cat >"$denovo_out/assembly/$denovo_row.read_density.tsv" <<EOF
contig	window_start	window_end	mean_depth
contig_1	0	10	38
contig_1	10	20	42
contig_1	20	30	39
contig_1	30	40	41
contig_2	0	10	19
contig_2	10	20	22
EOF
	cat >"$denovo_out/assembly/$denovo_row.read_density.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="240" viewBox="0 0 760 240" role="img" aria-label="Assembly read density preview">
  <rect width="760" height="240" fill="#fbfcfc"/>
  <text x="24" y="32" font-family="sans-serif" font-size="18" fill="#172026">Assembly read density</text>
  <line x1="70" y1="190" x2="720" y2="190" stroke="#8a98a3"/>
  <line x1="70" y1="54" x2="70" y2="190" stroke="#8a98a3"/>
  <text x="82" y="213" font-family="sans-serif" font-size="12" fill="#5d6a72">contig_1</text>
  <text x="560" y="213" font-family="sans-serif" font-size="12" fill="#5d6a72">contig_2</text>
  <polyline fill="none" stroke="#196b69" stroke-width="4" points="70,88 190,74 310,84 430,78 560,142 690,132"/>
  <text x="86" y="62" font-family="sans-serif" font-size="12" fill="#5d6a72">depth</text>
</svg>
EOF
	cat >"$denovo_out/assembly/$denovo_row.assembly_graph.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="260" viewBox="0 0 760 260" role="img" aria-label="Circular assembly graph preview">
  <rect width="760" height="260" fill="#fbfcfc"/>
  <text x="24" y="34" font-family="sans-serif" font-size="18" fill="#172026">Circular assembly graph preview</text>
  <circle cx="230" cy="140" r="72" fill="none" stroke="#196b69" stroke-width="12"/>
  <path d="M300 140 L338 126 L338 154 Z" fill="#196b69"/>
  <text x="181" y="145" font-family="sans-serif" font-size="14" fill="#172026">contig_1</text>
  <line x1="440" y1="140" x2="650" y2="140" stroke="#7a4f12" stroke-width="12" stroke-linecap="round"/>
  <text x="504" y="122" font-family="sans-serif" font-size="14" fill="#172026">contig_2</text>
  <text x="120" y="232" font-family="sans-serif" font-size="12" fill="#5d6a72">Toy preview: circularity needs assembler/read evidence review before biological interpretation.</text>
</svg>
EOF
	cat >"$denovo_out/pipeline_info/execution_report.html" <<'EOF'
<!doctype html><html><body><h1>denovo assembly preview pipeline info</h1></body></html>
EOF
	cat >"$denovo_out/report/denovo_assembly_summary.tsv" <<EOF
row_id	assembler	platform	contigs	total_bases	n50	longest_contig	circular_contigs	primary_fasta	primary_gfa	gfastats	hifiasm_log	read_summary	circularity	read_density_plot	assembly_graph
$denovo_row	hifiasm	hifi	2	60	40	40	1	$denovo_out/assembly/$denovo_row.primary.fasta	$denovo_out/assembly/$denovo_row.primary.gfa	$denovo_out/assembly/$denovo_row.gfastats.txt	$denovo_out/assembly/$denovo_row.hifiasm.log	$denovo_out/qc/$denovo_row.seqkit_stats.tsv	$denovo_out/assembly/$denovo_row.circularity.tsv	$denovo_out/assembly/$denovo_row.read_density.svg	$denovo_out/assembly/$denovo_row.assembly_graph.svg
EOF
	cat >"$denovo_out/report/denovo_assembly_manifest.json" <<EOF
{
  "pipeline": "denovo-assembly",
  "assembler": "hifiasm",
  "platform": "hifi",
  "reference_guide": "",
  "summary": [
    {
      "row_id": "$denovo_row",
      "assembler": "hifiasm",
      "platform": "hifi",
      "contigs": 2,
      "total_bases": 60,
      "n50": 40,
      "longest_contig": 40,
      "circular_contigs": 1,
      "primary_fasta": "$denovo_out/assembly/$denovo_row.primary.fasta",
      "primary_gfa": "$denovo_out/assembly/$denovo_row.primary.gfa",
      "gfastats": "$denovo_out/assembly/$denovo_row.gfastats.txt",
      "hifiasm_log": "$denovo_out/assembly/$denovo_row.hifiasm.log",
      "read_summary": "$denovo_out/qc/$denovo_row.seqkit_stats.tsv",
      "circularity": "$denovo_out/assembly/$denovo_row.circularity.tsv",
      "read_density": "$denovo_out/assembly/$denovo_row.read_density.tsv",
      "read_density_plot": "$denovo_out/assembly/$denovo_row.read_density.svg",
      "assembly_graph": "$denovo_out/assembly/$denovo_row.assembly_graph.svg"
    }
  ]
}
EOF
	cat >"$denovo_out/report/denovo_assembly_report.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome De Novo Assembly Report</title>
  <style>
    :root { color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #f7f8fa; color: #1c2024; }
    main { max-width: 1120px; margin: 0 auto; padding: 32px 20px 48px; }
    h1 { margin: 0 0 8px; font-size: clamp(2rem, 5vw, 3.2rem); line-height: 1.05; }
    .lede { max-width: 820px; color: #4a515c; font-size: 1.05rem; line-height: 1.6; }
    .sample { margin-top: 22px; padding: 20px; border: 1px solid #d9dee7; border-radius: 8px; background: white; }
    .artifact-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 12px; margin: 18px 0; }
    .artifact-grid a { display: block; padding: 12px; border: 1px solid #d9dee7; border-radius: 8px; color: inherit; text-decoration: none; }
    dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin: 18px 0; }
    dt { color: #65707f; font-size: 0.82rem; }
    dd { margin: 4px 0 0; font-size: 1.45rem; font-weight: 700; }
    .note { margin-top: 24px; padding: 16px 18px; border-left: 4px solid #2b6cb0; background: #edf5ff; color: #20364f; }
    @media (prefers-color-scheme: dark) {
      body { background: #111417; color: #eef1f5; }
      .lede { color: #bac4cf; }
      .sample { background: #171b20; border-color: #2d3642; }
      dt { color: #aab5c2; }
      .note { background: #162433; color: #d8e9ff; }
    }
  </style>
</head>
<body>
  <main>
    <h1>De Novo Assembly Report</h1>
    <p class="lede">This preview summarizes the user-facing output from a local long-read assembly. It mirrors the published report contract without running hifiasm, Flye, Verkko, or gfastats.</p>
    <section class="sample">
      <h2>$denovo_row</h2>
      <p><strong>Assembler:</strong> hifiasm · <strong>Platform:</strong> hifi</p>
      <dl>
        <div><dt>Contigs</dt><dd>2</dd></div>
        <div><dt>Total assembled bases</dt><dd>60</dd></div>
        <div><dt>N50</dt><dd>40</dd></div>
        <div><dt>Longest contig</dt><dd>40</dd></div>
        <div><dt>Circular contigs</dt><dd>1</dd></div>
      </dl>
      <p>The FASTA is the assembled sequence. The GFA keeps the assembly graph, which is useful when checking repeats, bubbles, and unresolved regions.</p>
      <h3>Assembly review artifacts</h3>
      <div class="artifact-grid">
        <a href="../assembly/$denovo_row.circularity.tsv"><strong>Circularity table</strong><br>Terminal-overlap review for contigs.</a>
        <a href="../assembly/$denovo_row.read_density.svg"><strong>Read density plot</strong><br>Coverage-like density across assembled contigs.</a>
        <a href="../assembly/$denovo_row.assembly_graph.svg"><strong>Assembly graph preview</strong><br>Visual circular/linear contig sketch.</a>
        <a href="../assembly/$denovo_row.gfastats.txt"><strong>gfastats output</strong><br>Raw continuity metrics.</a>
      </div>
    </section>
    <div class="note">N50 is a contiguity metric, not a health or ancestry result. Higher is often better for assemblies, but coverage, read quality, contamination, and collapsed repeats still need review.</div>
  </main>
</body>
</html>
EOF
}

publish_variant_outputs "$reference_row" "$sample_id" "$reference_out" "$reference_samplesheet" "reference-germline"
publish_variant_outputs "$vcf_row" "$sample_id" "$existing_vcf_out" "$vcf_samplesheet" "existing-vcf"
publish_denovo_outputs

cp "$reference_out/report/findings.tsv" "$index_report_dir/findings.tsv"
cp "$reference_out/report/evidence.json" "$index_report_dir/evidence.json"
cp "$reference_out/report/run_manifest.json" "$index_report_dir/run_manifest.json"

cat >"$index_report_dir/report_index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome Demo Outputs</title>
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
    <h1>Open Genome Demo Outputs</h1>
    <p>This local preview bundle shows the public-facing outputs Open Genome produces for variant and assembly workflows. It is generated from tiny bundled fixtures, so users can inspect reports and file layout without rerunning heavy workflows.</p>
    <div class="grid">
      <a class="card" href="../reference-germline/report/report_index.html"><strong>Reference germline report</strong>FASTQ to fastp/FastQC/MultiQC-style QC, read-density preview, alignment, normalized variants, annotations, mitochondrial summary, evidence JSON, and findings TSV.</a>
      <a class="card" href="../existing-vcf/report/report_index.html"><strong>Existing VCF report</strong>Report-only VCF normalization, local annotation evidence, consequence summary, and findings.</a>
      <a class="card" href="../denovo-assembly/report/denovo_assembly_report.html"><strong>De novo assembly report</strong>Long-read assembly FASTA/GFA, circularity review, read-density plot, assembly graph preview, gfastats continuity metrics, summary TSV, and assembly manifest.</a>
    </div>
    <section class="files">
      <p><strong>Results folder:</strong> <code>$outdir</code></p>
      <p><strong>Reference FASTA:</strong> <code>$reference</code></p>
      <p><strong>Samplesheets:</strong> <code>$samples_dir</code></p>
    </section>
  </main>
</body>
</html>
EOF

open_genome_paths_set workdir "$workdir"
open_genome_paths_set dataset "$dataset_dir"
open_genome_manifest_set reference.fasta "$reference"
open_genome_manifest_set reference.fai "$reference.fai"
open_genome_manifest_set reference.dict "$reference_dir/tiny_grch38_smoke.dict"
open_genome_manifest_set sample.samplesheet "$reference_samplesheet"
open_genome_manifest_set sample.input_dir "$dataset_dir"
open_genome_manifest_set sample.input_type "demo_preview"
open_genome_manifest_set sample.recommended_plan "Bundled demo preview: reference germline, existing VCF, de novo assembly"
open_genome_manifest_set workflow.outdir "$outdir"
open_genome_manifest_set workflow.recommended_plan "Bundled demo preview: reference germline, existing VCF, de novo assembly"
open_genome_manifest_set results.report_dir "$index_report_dir"
open_genome_manifest_set results.report_html "$index_report_dir/report_index.html"
open_genome_manifest_set results.findings_tsv "$index_report_dir/findings.tsv"
open_genome_manifest_set results.evidence_json "$index_report_dir/evidence.json"
open_genome_manifest_set results.denovo_report_dir "$denovo_out/report"
open_genome_manifest_set results.denovo_report_html "$denovo_out/report/denovo_assembly_report.html"
open_genome_manifest_set results.denovo_summary_tsv "$denovo_out/report/denovo_assembly_summary.tsv"
open_genome_manifest_set results.denovo_manifest_json "$denovo_out/report/denovo_assembly_manifest.json"

echo "Demo outputs generated in the Open Genome work folder."
echo ""
echo "  Work folder:               $workdir"
echo "  Results folder:            $outdir"
echo "  Preview index:             $index_report_dir/report_index.html"
echo "  Reference germline report: $reference_out/report/report_index.html"
echo "  Existing VCF report:       $existing_vcf_out/report/report_index.html"
echo "  De novo assembly report:   $denovo_out/report/denovo_assembly_report.html"
echo ""
echo "The manifest and setup checklist now track the preview bundle."
echo ""
echo "Next: Results -> Open my report, or Results -> Explain my results."
