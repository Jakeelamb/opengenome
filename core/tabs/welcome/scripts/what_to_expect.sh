#!/usr/bin/env sh
set -e

cat <<'EOF'
What to expect

1. Start Here -> Start guided setup
   Choose the work/results folder.
   Select sequencing files or an input folder.
   Optionally choose a reference.
   The checklist updates from the saved manifest.
   If you are unsure, keep the recommended defaults.

2. Start Here -> Check what is ready
   Run the read-only checklist for full details.

3. Run Analysis -> Run reference-based analysis
   Align reads or use BAM/CRAM, run QC, call variants, and build a report.
   Illumina FASTQ defaults to BWA-MEM2 + GATK.
   PacBio HiFi/CCS and ONT reference runs default to Clair3.

4. Run Analysis -> Run existing VCF report
   Existing VCFs use a report-only workflow.
   No alignment or variant calling is performed.
   Open Genome writes the exact command file.
   Runs can be reviewed, repeated, or resumed.

5. Run Analysis -> Run de novo assembly
   Use this for long-read assembly experiments.
   PacBio HiFi/CCS defaults to hifiasm.
   ONT-only reads default to Flye.
   Human-scale assembly can need high RAM and disk.

6. Results -> Open my report
   Review the generated HTML report and evidence files.
   Reports summarize local evidence and quality signals.
   They do not provide diagnosis or treatment advice.

For development and release checks, Open Genome keeps tiny
local smoke datasets. They verify setup, pipeline stubs,
and report generation without private genome files.
EOF
