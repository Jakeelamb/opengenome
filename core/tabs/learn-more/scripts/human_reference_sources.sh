#!/usr/bin/env sh
set -e

cat <<'EOF'
Open Genome - Human reference sources

There is not one universal "latest human reference" for every workflow.
Pick the reference that matches your aligner indexes, annotations, VCFs,
models, and downstream interpretation resources.

Practical default for most WGS pipelines today:
  GRCh38 / hg38
  Use this when you need broad compatibility with GATK, ClinVar, dbSNP,
  gnomAD, Ensembl VEP, SnpEff, IGV tracks, and most public callsets.

Current patched GRCh38 line:
  GRCh38.p14 at NCBI:
    https://www.ncbi.nlm.nih.gov/datasets/genome/GCF_000001405.40/
  Ensembl human GRCh38.p14:
    https://www.ensembl.org/Homo_sapiens/Info/Index
  GENCODE human release page:
    https://www.gencodegenes.org/human/

Workflow-compatible GRCh38 bundles:
  Broad/GATK hg38 resource mirror used by Open Genome:
    https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/
  GATK reference-build notes:
    https://gatk.broadinstitute.org/hc/en-us/articles/360035890951-Human-genome-reference-builds-GRCh38-or-hg38-b37-hg19
  UCSC hg38 downloads:
    https://hgdownload.soe.ucsc.edu/goldenpath/hg38/bigZips/
  NCI GDC GRCh38.d1.vd1 reference:
    https://gdc.cancer.gov/about-data/gdc-data-processing/gdc-reference-files

Complete T2T reference:
  T2T-CHM13v2.0 at NCBI:
    https://www.ncbi.nlm.nih.gov/assembly/11828891
  T2T-CHM13 source/download repository:
    https://github.com/marbl/CHM13
  UCSC T2T-CHM13 browser assembly:
    https://genome.ucsc.edu/cgi-bin/hgGateway?genome=hs1

How to choose:
  - Use GRCh38/hg38 for maximum tool/model/annotation compatibility.
  - Use a GATK/Broad hg38 bundle when running GATK-style short-read pipelines.
  - Use T2T-CHM13 when the workflow, annotations, callsets, and comparisons are
    explicitly built for CHM13 coordinates.
  - Do not mix references. FASTA, .fai, .dict, BAM/CRAM, VCF, ClinVar/dbSNP,
    gnomAD, VEP/SnpEff annotations, and model files must agree on coordinates.
EOF
