#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Open Genome - Good Free V1 report sources

Goal:
  Provide a 23andMe-style digestible report, but keep source data,
  confidence, limitations, and raw tables visible.

Area: Raw read QC
Tools/data: fastp, FastQC, MultiQC
User gets: sequencing usability, low-quality reads, adapter contamination.

Area: Alignment QC
Tools/data: samtools, mosdepth, bcftools stats
User gets: coverage, mapped reads, variant counts, transition/transversion ratio.

Area: Assembly QC
Tools/data: gfastats, QUAST
User gets: N50/L50, contig counts, GC, and an assembly quality report.
Status: gfastats is in the base env; QUAST is useful but optional because it
  pulls a larger plotting/R/Perl dependency set.

Area: Variant IDs
Tools/data: dbSNP
User gets: rsIDs for variants. Useful labels, not interpretation.

Area: Clinical variant matches
Tools/data: ClinVar VCF/XML
User gets: whether a variant has been submitted as pathogenic,
  likely pathogenic, uncertain, likely benign, or benign.

Area: Population frequency
Tools/data: gnomAD, 1000 Genomes / IGSR
User gets: common/rare context in reference populations to avoid overcalling.

Area: Gene/disease curation
Tools/data: ClinGen
User gets: gene-disease validity, dosage sensitivity, and actionability context.

Area: Variant consequence
Tools/data: Ensembl VEP or SnpEff/SnpSift
User gets: missense, stop-gain, splice, gene/transcript effect.
Status: later/on demand; VEP is useful but heavier than V1 needs.

Area: Pharmacogenomics
Tools/data: PharmCAT + CPIC/ClinPGx
User gets: drug-response report with strong disclaimers.
Status: later/on demand; useful but interpretation-heavy.

Area: Report generation
Tools/data: static HTML, TSV, JSON
User gets: clean consumer report plus raw truth tables.

Added to base:
  - gfastats

Optional/on demand:
  - quast
  - ensembl-vep
  - PharmCAT
  - large local gnomAD caches
  - polygenic scores
  - ancestry inference
EOF
