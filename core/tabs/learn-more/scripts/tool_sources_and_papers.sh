#!/usr/bin/env sh
set -e

cat <<'EOF'
Open Genome - Tools, source code, and papers

Workflow engines and test tools
  Nextflow
    Source: https://github.com/nextflow-io/nextflow
    Docs:   https://www.nextflow.io/docs/latest/
    Paper:  https://doi.org/10.1038/nbt.3820
  nf-test
    Source: https://github.com/askimed/nf-test
    Docs:   https://www.nf-test.com/
    Paper:  https://doi.org/10.1093/gigascience/giaf130

Read QC and report aggregation
  fastp
    Source: https://github.com/OpenGene/fastp
    Paper:  https://doi.org/10.1093/bioinformatics/bty560
  FastQC
    Source/docs: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
  MultiQC
    Source: https://github.com/MultiQC/MultiQC
    Docs:   https://docs.seqera.io/multiqc
    Paper:  https://doi.org/10.1093/bioinformatics/btw354

Alignment, BAM/CRAM/VCF, and coverage
  BWA
    Source: https://github.com/lh3/bwa
    Paper:  https://doi.org/10.1093/bioinformatics/btp324
  BWA-MEM2
    Source: https://github.com/bwa-mem2/bwa-mem2
    Paper/preprint: https://doi.org/10.1101/2020.10.02.324830
  minimap2
    Source: https://github.com/lh3/minimap2
    Paper:  https://doi.org/10.1093/bioinformatics/bty191
  pbmm2
    Source: https://github.com/PacificBiosciences/pbmm2
  SAMtools / BCFtools / HTSlib
    Source: https://github.com/samtools
    Paper:  https://doi.org/10.1093/gigascience/giab008
  mosdepth
    Source: https://github.com/brentp/mosdepth
    Paper:  https://doi.org/10.1093/bioinformatics/btx699
  BEDTools
    Source: https://github.com/arq5x/bedtools2
    Paper:  https://doi.org/10.1093/bioinformatics/btq033
  Picard
    Source: https://github.com/broadinstitute/picard
    Docs:   https://broadinstitute.github.io/picard/

Variant calling and phasing
  GATK
    Source: https://github.com/broadinstitute/gatk
    Docs:   https://gatk.broadinstitute.org/
    Paper:  https://doi.org/10.1101/gr.107524.110
  DeepVariant
    Source: https://github.com/google/deepvariant
    Paper:  https://doi.org/10.1038/nbt.4235
  Clair3
    Source: https://github.com/HKU-BAL/Clair3
    Paper:  https://doi.org/10.1038/s43588-022-00387-x
  Sniffles
    Source: https://github.com/fritzsedlazeck/Sniffles
    Paper:  https://doi.org/10.1038/s41592-018-0001-7
  cuteSV
    Source: https://github.com/tjiangHIT/cuteSV
    Paper:  https://doi.org/10.1093/bioinformatics/btaa1014
  WhatsHap
    Source: https://github.com/whatshap/whatshap
    Paper:  https://doi.org/10.1038/nmeth.3672

De novo long-read assembly and assembly review
  hifiasm
    Source: https://github.com/chhylp123/hifiasm
    Paper:  https://doi.org/10.1038/s41592-020-01056-5
  Flye
    Source: https://github.com/mikolmogorov/Flye
    Paper:  https://doi.org/10.1038/s41587-019-0072-8
  Verkko
    Source: https://github.com/marbl/verkko
    Paper:  https://doi.org/10.1038/s41587-023-01662-6
  gfastats
    Source: https://github.com/vgl-hub/gfastats
    Paper:  https://doi.org/10.1093/bioinformatics/btac460
  SeqKit
    Source: https://github.com/shenwei356/seqkit
    Paper:  https://doi.org/10.1371/journal.pone.0163962

Annotation, interpretation context, and public datasets
  Ensembl VEP
    Source: https://github.com/Ensembl/ensembl-vep
    Docs:   https://www.ensembl.org/info/docs/tools/vep/
    Paper:  https://doi.org/10.1186/s13059-016-0974-4
  SnpEff / SnpSift
    Source: https://github.com/pcingola/SnpEff
    Paper:  https://doi.org/10.4161/fly.19695
  PharmCAT
    Source: https://github.com/PharmGKB/PharmCAT
    Docs:   https://pharmcat.org/
  ClinVar
    Source/data: https://www.ncbi.nlm.nih.gov/clinvar/
    Paper:       https://doi.org/10.1093/nar/gkv1222
  dbSNP
    Source/data: https://www.ncbi.nlm.nih.gov/snp/
    Paper:       https://doi.org/10.1093/nar/gkq1027
  gnomAD
    Source/data: https://gnomad.broadinstitute.org/
    Paper:       https://doi.org/10.1038/s41586-020-2308-7
  GENCODE
    Source/data: https://www.gencodegenes.org/
    Paper:       https://doi.org/10.1093/nar/gkae1078

Visualization
  IGV desktop
    Source: https://github.com/igvteam/igv
    Docs:   https://igv.org/doc/desktop/
    Paper:  https://doi.org/10.1093/bib/bbs017
  igv.js
    Source: https://github.com/igvteam/igv.js
    Docs:   https://igv.org/doc/igvjs/
    Paper:  https://doi.org/10.1093/bioinformatics/btab139

General command-line helpers used by Open Genome environments
  csvtk:  https://github.com/shenwei356/csvtk
  jq:     https://github.com/jqlang/jq
  pigz:   https://zlib.net/pigz/
  curl:   https://github.com/curl/curl
  wget:   https://www.gnu.org/software/wget/
EOF
