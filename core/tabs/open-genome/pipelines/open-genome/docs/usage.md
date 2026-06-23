# OpenGenome Reference Germline Usage

This workflow runs reference-based germline analysis for one local genome sample.

## Accepted Inputs

The samplesheet must contain only these `input_type` values:

- `fastq`: paired Illumina FASTQ rows with `fastq_1` and `fastq_2`.
- `long_reads`: PacBio HiFi or ONT reads in `long_reads`.
- `alignment`: existing BAM or CRAM in `bam` or `cram`.

Use `../vcf-annotate` for existing VCF files. Use `../denovo-assembly` for de novo assembly.

## Presets

The TUI should prefer preset files from `../presets/`:

- `illumina_wgs_gatk.yml`
- `pacbio_hifi_clair3.yml`
- `ont_clair3.yml`

If users do not know what to choose, the TUI chooses the safest local default from the samplesheet: paired short reads use BWA-MEM2 plus GATK, PacBio HiFi/CCS long reads use pbmm2/minimap2 plus Clair3 `hifi`, and ONT long reads use minimap2 plus Clair3 `ont`. This is a sequencing-platform default, not a generic ranking of callers. DeepVariant remains available as an explicit external caller when users provide a compatible executable/container path. Expert overrides are still available through Nextflow params and environment variables used by the run-preparation scripts.

Clair3 background: Zheng et al., [Symphonizing pileup and full-alignment for deep learning-based long-read variant calling](https://doi.org/10.1038/s43588-022-00387-x), Nature Computational Science 2022; Zheng et al., [Accelerated long-read variant calling with Clair3 for whole-genome sequencing](https://doi.org/10.1093/bioinformatics/btag181), Bioinformatics 2026.

## Minimal Command

```bash
nextflow run core/tabs/open-genome/pipelines/open-genome \
  -profile opengenome \
  --samplesheet /path/to/open_genome_samplesheet.csv \
  --input_dir /path/to/selected-input-folder \
  --outdir /path/to/results \
  --max_cpus 8 \
  --fasta /path/to/reference.fa \
  --fasta_fai /path/to/reference.fa.fai \
  --dict /path/to/reference.dict
```

## Profiles

- `opengenome`: local execution used by the TUI.
- `conda`: local execution with the bundled `opengenome` conda environment.
- `docker`: container execution placeholder for release packaging.
- `apptainer`: Apptainer execution placeholder for workstation/HPC packaging.
- `stub`: fast graph smoke tests with `-stub-run`.
- `test`: bounded resources for tiny local tests.

## Local-Only Boundary

Reads, alignments, VCFs, logs, and reports stay on the local machine. The TUI run preparation passes the saved input folder as `--input_dir`, the saved output folder as `--outdir`, and the saved CPU limit as `--max_cpus`; runnable file paths still come from the generated samplesheet so individual FASTQ/BAM/CRAM rows are explicit and reproducible. Optional public resources such as dbSNP, ClinVar, gnomAD, VEP/SnpEff data, and PharmCAT are read from local paths only.
