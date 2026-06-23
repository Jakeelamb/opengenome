# OpenGenome De Novo Assembly Usage

This workflow assembles long-read data and produces a local assembly report.

## Accepted Inputs

The samplesheet must contain only `input_type=long_reads` rows with a populated `long_reads` column.

True HiFi plus ultra-long ONT hybrid assembly requires a future samplesheet version with separate read streams. Until then, `hybrid_denovo_verkko.yml` is documented as a deferred preset.

## Presets

- `hifi_denovo_hifiasm.yml`
- `ont_denovo_flye.yml`
- `hybrid_denovo_verkko.yml` (deferred until samplesheet v2)

If no assembler override is set, the TUI chooses hifiasm for HiFi/CCS reads and Flye for ONT-only reads. Set `OPEN_GENOME_ASSEMBLER=hifiasm`, `flye`, or `verkko` only when you intentionally want to override that recommendation.

Flye defaults to `--nano-hq` for ONT and `--pacbio-hifi` for HiFi when `--flye_read_type auto` is used. Advanced users can set `--flye_read_type pacbio-corr`, `pacbio-raw`, `nano-corr`, or `nano-raw` for corrected or older read sets.

## Minimal Command

```bash
nextflow run core/tabs/open-genome/pipelines/denovo-assembly \
  -profile opengenome \
  --samplesheet /path/to/open_genome_samplesheet.csv \
  --input_dir /path/to/selected-input-folder \
  --outdir /path/to/assembly-results \
  --max_cpus 16 \
  --assembler hifiasm \
  --long_read_platform hifi \
  --genome_size 3g
```

## Profiles

- `opengenome`: local execution used by the TUI.
- `conda`: local execution with the bundled `opengenome-denovo` conda environment.
- `docker`: container execution placeholder for release packaging.
- `apptainer`: Apptainer execution placeholder for workstation/HPC packaging.
- `stub`: fast graph smoke tests with `-stub-run`.
- `test`: bounded resources for tiny local tests.

Human-scale assembly can require substantial RAM, CPU, and scratch disk. The TUI run preparation passes the saved CPU limit as `--max_cpus` and `--assembler_threads`, passes the selected sequencing folder as `--input_dir` for provenance, and writes outputs only under the selected `--outdir`. It defaults `--genome_size` to `3g` for human assemblies and exposes `OPEN_GENOME_DENOVO_GENOME_SIZE`, `OPEN_GENOME_DENOVO_MEMORY`, `OPEN_GENOME_ASSEMBLER`, `OPEN_GENOME_LONG_READ_PLATFORM`, and `OPEN_GENOME_FLYE_READ_TYPE` for expert overrides.
