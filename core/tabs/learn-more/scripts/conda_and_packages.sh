#!/usr/bin/env sh
set -e

cat <<'EOF'
Open Genome - Conda and package projects

Open Genome installs most command-line genomics tools through local Conda
environments. Your sequence data is not uploaded to Conda, conda-forge, or
Bioconda; packages are downloaded to this machine.

Conda ecosystem
  Conda project:
    https://conda.org/
  Conda source:
    https://github.com/conda/conda
  Conda documentation:
    https://docs.conda.io/
  Miniforge installer:
    https://github.com/conda-forge/miniforge
  conda-forge:
    https://conda-forge.org/
    https://github.com/conda-forge
  Bioconda:
    https://bioconda.github.io/
    https://github.com/bioconda/bioconda-recipes
  Bioconda paper:
    https://doi.org/10.1038/s41592-018-0046-7

Open Genome environments
  Main workflow environment:
    core/tabs/open-genome/modules/opengenome/environment.yml
  De novo assembly environment:
    core/tabs/open-genome/modules/denovo_assembly/environment.yml

Current package roles
  opengenome:
    read QC, alignment, coverage, GATK/Clair3 reference workflows,
    VCF handling, report support, IGV launch support.

  opengenome-denovo:
    hifiasm, Flye, Verkko, minimap2, samtools, gfastats, and SeqKit for
    long-read de novo assembly plus assembly review artifacts.

Useful package search pages
  bioconda package index:
    https://bioconda.github.io/recipes.html
  conda-forge package index:
    https://conda-forge.org/packages/
EOF
