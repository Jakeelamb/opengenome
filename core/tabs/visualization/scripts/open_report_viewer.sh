#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
report=$(open_genome_manifest_get results.report_html)
outdir=$(open_genome_manifest_get workflow.outdir)

is_scratch_path() {
	case "$1" in
		*/nextflow-work-* | */nextflow-work-*/* | */.nextflow | */.nextflow/*) return 0 ;;
		*) return 1 ;;
	esac
}

if test -n "$report" && is_scratch_path "$report"; then
	report=""
fi

if test -z "$report" || ! test -f "$report"; then
	if test -n "$outdir"; then
		report=$(find "$outdir" \
			\( -path '*/nextflow-work-*' -o -path '*/.nextflow' \) -prune -o \
			-type f -name 'report_index.html' -print 2>/dev/null | sort | head -n 1 || true)
		if test -z "$report"; then
			report=$(find "$outdir" \
				\( -path '*/nextflow-work-*' -o -path '*/.nextflow' \) -prune -o \
				-type f -name 'open_genome_report.html' -print 2>/dev/null | sort | head -n 1 || true)
		fi
		if test -z "$report"; then
			report=$(find "$outdir" \
				\( -path '*/nextflow-work-*' -o -path '*/.nextflow' \) -prune -o \
				-type f -name 'denovo_assembly_report.html' -print 2>/dev/null | sort | head -n 1 || true)
		fi
	fi
fi

if test -z "$report" || ! test -f "$report"; then
	echo "No Open Genome report found."
	echo "Run Analysis -> Run reference-based analysis, Run existing VCF report, or Run de novo assembly first; or use Start Here -> Load existing results."
	exit 1
fi

report_dir=$(dirname -- "$report")
open_genome_manifest_set results.report_dir "$report_dir"
open_genome_manifest_set results.report_html "$report"
if test -f "$report_dir/findings.tsv"; then
	open_genome_manifest_set results.findings_tsv "$report_dir/findings.tsv"
fi
if test -f "$report_dir/evidence.json"; then
	open_genome_manifest_set results.evidence_json "$report_dir/evidence.json"
fi

echo "Open Genome report:"
echo "  $report"
echo ""

if test "${OPEN_GENOME_OPEN_REPORT_DRY_RUN:-}" = "1"; then
	exit 0
fi

report_uri=$(REPORT_PATH=$report python3 - <<'PY'
import os
from pathlib import Path

print(Path(os.environ["REPORT_PATH"]).resolve().as_uri())
PY
)

try_open_report() {
	label=$1
	shift
	log_file=$(mktemp "${TMPDIR:-/tmp}/open-genome-report-open.XXXXXX")
	setsid "$@" "$report_uri" >"$log_file" 2>&1 &
	pid=$!
	sleep 0.5
	if kill -0 "$pid" 2>/dev/null; then
		echo "Launched report with $label."
		echo "If no browser window appeared, open this URL manually:"
		echo "  $report_uri"
		rm -f "$log_file"
		return 0
	fi
	if wait "$pid"; then
		echo "Launched report with $label."
		rm -f "$log_file"
		return 0
	fi
	echo "$label failed to open the report." >&2
	if test -s "$log_file"; then
		cat "$log_file" >&2
	fi
	rm -f "$log_file"
	return 1
}

if test -n "${OPEN_GENOME_REPORT_OPENER:-}"; then
	try_open_report "$OPEN_GENOME_REPORT_OPENER" "$OPEN_GENOME_REPORT_OPENER"
elif command -v xdg-open >/dev/null 2>&1 && try_open_report xdg-open xdg-open; then
	:
elif command -v gio >/dev/null 2>&1 && try_open_report "gio open" gio open; then
	:
elif command -v sensible-browser >/dev/null 2>&1 && try_open_report sensible-browser sensible-browser; then
	:
elif command -v open >/dev/null 2>&1 && try_open_report open open; then
	:
else
	echo "No desktop opener found. Open this URL in your browser:"
	echo "  $report_uri"
fi
