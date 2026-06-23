# OpenGenome Existing VCF Report Usage

This workflow normalizes and reports existing VCF files. It does not align reads or call variants.

## Accepted Inputs

The samplesheet must contain only `input_type=vcf` rows with a populated `vcf` column.

Use `../open-genome` for FASTQ/BAM/CRAM reference-based germline analysis. Use `../denovo-assembly` for long-read assembly.

## Minimal Command

```bash
nextflow run core/tabs/open-genome/pipelines/vcf-annotate \
  -profile opengenome \
  --samplesheet /path/to/open_genome_samplesheet.csv \
  --input_dir /path/to/selected-input-folder \
  --outdir /path/to/results \
  --max_cpus 2 \
  --fasta /path/to/reference.fa
```

## Profiles

- `opengenome`: local execution used by the TUI.
- `conda`: local execution with the bundled `opengenome` conda environment.
- `docker`: container execution placeholder for release packaging.
- `apptainer`: Apptainer execution placeholder for workstation/HPC packaging.
- `stub`: fast graph smoke tests with `-stub-run`.
- `test`: bounded resources for tiny local tests.

## Local Evidence

dbSNP, ClinVar, gnomAD, VEP/SnpEff consequence fields, and PharmCAT are optional local resources. Missing resources are recorded as skipped rather than queried remotely.

The TUI run preparation passes the saved input folder as `--input_dir`, the saved output folder as `--outdir`, and the saved CPU limit as `--max_cpus`; runnable VCF file paths come from the generated samplesheet.
