#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
MANIFEST_CLI="$REPO/core/tabs/open-genome/lib/manifest_cli.py"
DEFAULT_MANIFEST="$REPO/core/tabs/open-genome/manifest.default.toml"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_GENOME_CONFIG_DIR="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"
export OPEN_GENOME_HUMAN_VALIDATION_TEST_MODE=1
export OPEN_GENOME_HUMAN_VALIDATION_TARGET_COVERAGE=7
export PATH="$tmp/bin:$PATH"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/nextflow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

pipeline=
outdir=
log=
prev=
for arg in "$@"; do
	case "$prev" in
		run) pipeline=$arg ;;
		-log) log=$arg ;;
		--outdir) outdir=$arg ;;
	esac
	prev=$arg
done

test -n "$outdir"
mkdir -p "$outdir"
test -n "$log" && mkdir -p "$(dirname "$log")" && printf 'fake nextflow\n' >"$log"

case "$pipeline" in
	*/open-genome)
		mkdir -p "$outdir/report" "$outdir/variants" "$outdir/alignment" "$outdir/qc"
		printf '<html>reference</html>\n' >"$outdir/report/report_index.html"
		printf 'sample\trow_id\tsection\tfinding\nHG003\tHG003_hifi_7x\tCoverage\tCoverage summary generated\n' >"$outdir/report/findings.tsv"
		printf '{"rows":[],"counts":{},"files":{}}\n' >"$outdir/report/evidence.json"
		printf '{}\n' >"$outdir/report/run_manifest.json"
		printf '##fileformat=VCFv4.2\n' >"$outdir/variants/HG003_hifi_7x.normalized.vcf.gz"
		printf 'bam\n' >"$outdir/alignment/HG003_hifi_7x.sorted.bam"
		printf '<html>multiqc</html>\n' >"$outdir/qc/multiqc_report.html"
		;;
	*/vcf-annotate)
		mkdir -p "$outdir/report" "$outdir/variants" "$outdir/annotations"
		printf '<html>vcf</html>\n' >"$outdir/report/report_index.html"
		printf 'sample\trow_id\tsection\tfinding\nHG003\tHG003_hifi_7x_vcf\tVariants\tVariants normalized and summarized\n' >"$outdir/report/findings.tsv"
		printf '{"rows":[],"counts":{},"files":{}}\n' >"$outdir/report/evidence.json"
		printf '{}\n' >"$outdir/report/run_manifest.json"
		printf '##fileformat=VCFv4.2\n' >"$outdir/variants/HG003_hifi_7x_vcf.normalized.vcf.gz"
		printf 'chrom\tpos\tid\tref\talt\tgt\n' >"$outdir/annotations/HG003_hifi_7x_vcf.variant_summary.tsv"
		;;
	*/denovo-assembly)
		mkdir -p "$outdir/report" "$outdir/assembly"
		printf '<html>denovo</html>\n' >"$outdir/report/denovo_assembly_report.html"
		printf 'row_id\tassembler\tplatform\tcontigs\ttotal_bases\tn50\tlongest_contig\tprimary_fasta\tprimary_gfa\tgfastats\thifiasm_log\tread_summary\nHG003_hifi_7x_denovo\thifiasm\thifi\t1\t32\t32\t32\tassembly.fa\tassembly.gfa\tstats\tlog\treads\n' >"$outdir/report/denovo_assembly_summary.tsv"
		printf '{"pipeline":"denovo-assembly","summary":[]}\n' >"$outdir/report/denovo_assembly_manifest.json"
		printf '>contig\nACGT\n' >"$outdir/assembly/HG003_hifi_7x_denovo.primary.fasta"
		printf 'S\tcontig\tACGT\n' >"$outdir/assembly/HG003_hifi_7x_denovo.primary.gfa"
		;;
	*)
		printf 'unexpected pipeline: %s\n' "$pipeline" >&2
		exit 1
		;;
esac
EOF
chmod +x "$tmp/bin/nextflow"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST" >/dev/null

output=$(bash "$HERE/run_human_validation_dataset.sh")
grep -q "Human validation outputs generated and loaded" <<<"$output"

workdir=$(python3 "$MANIFEST_CLI" get paths.workdir)
outdir=$(python3 "$MANIFEST_CLI" get workflow.outdir)
report_html=$(python3 "$MANIFEST_CLI" get results.report_html)
denovo_report=$(python3 "$MANIFEST_CLI" get results.denovo_report_html)
samplesheet=$(python3 "$MANIFEST_CLI" get sample.samplesheet)

[[ "$outdir" == "$workdir/open-genome-human-validation-results" ]]
[[ "$report_html" == "$outdir/report/report_index.html" ]]
[[ "$denovo_report" == "$outdir/denovo-assembly/report/denovo_assembly_report.html" ]]
[[ "$samplesheet" == "$workdir/human-validation-inputs/hg003-hifi-chr20-7x/reference_samplesheet.csv" ]]
test -s "$outdir/reference-germline/report/report_index.html"
test -s "$outdir/existing-vcf/report/report_index.html"
test -s "$outdir/denovo-assembly/report/denovo_assembly_report.html"

mv "$tmp/bin/nextflow" "$tmp/bin/nextflow.disabled"
reload=$(bash "$HERE/run_human_validation_dataset.sh")
grep -q "Loaded existing human validation results" <<<"$reload"

printf 'ok - human validation dataset action runs once and reloads existing outputs\n'
