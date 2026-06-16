# Open Genome bundle (modular)

This directory is embedded next to the tab trees and extracted at runtime with the TUI.

## Layout

| Path | Role |
|------|------|
| `manifest.default.toml` | Shipped defaults for local paths, privacy, sample import, GRCh38 resources, native workflow state, cache paths, results, and module toggles. Copied to `~/.config/open-genome/manifest.toml` on first use. |
| `lib/manifest_cli.py` | Read/write manifest (Python 3.11+ `tomllib`). |
| `lib/sample_scan.py` | Scan a local sequencing folder and emit Open Genome plus optional Sarek-compatible samplesheets. |
| `lib/report_compiler.py` | Compile pipeline outputs into static HTML/TSV/JSON evidence artifacts. |
| `pipelines/open-genome/` | Native Nextflow DSL2 pipeline for FASTQ, BAM/CRAM, VCF, and assembly-stat inputs. |
| `lib/conda_resolve.sh` | Pick `conda` from manifest + PATH, with explicit override support. |
| `lib/conda_install_module.sh` | `conda env create` / `env update` from a module `environment.yml`, with optional explicit-lock support when a maintained lock file exists. |
| `modules/<id>/module.toml` | Human metadata (`id`, `display_name`, `description`). |
| `modules/<id>/environment.yml` | Conda spec: `name:` becomes the env name; channels + packages. |
| `modules/<id>/environment.lock.*.txt` | Optional explicit conda lock for matching platforms when maintained for that module. |

## V1 local WGS flow

1. Setup -> Install private Miniforge/Conda.
2. Setup -> Install / update: Open Genome env.
3. Setup -> Scan sequencing folder. This writes local row-id based Open Genome and Sarek-compatible CSVs and records only local file paths.
4. Resources -> Set up local annotation cache, then Assembly -> Fetch/index configured GRCh38 reference.
5. Assembly -> Prepare Open Genome native run, then Run / resume Open Genome native workflow.
6. Visualization -> Summarize local workflow outputs, optionally launch IGV from the separate genome browser env.
7. Reports -> Review the free V1 report sources and interpretation boundaries.

Open Genome may download public tools, nf-core/sarek, and reference resources, but user reads, BAM/CRAM, VCF, logs, and metadata stay local.

Run `scripts/check-genomics.sh` from the repo root to verify Python scanner/report tests, shell syntax, Rust tab metadata, and the native Nextflow stub graph.

## Adding a module

1. Create `modules/<id>/` with `module.toml` + `environment.yml` (`name: og-<something>` unique).
2. Append `[[modules]]` with `id = "<id>"` and `enabled = true` in `manifest.default.toml` (and in your user manifest if you already copied it).
3. Add a thin wrapper in `../setup/scripts/conda_install_<id>.sh` that exports `OPEN_GENOME_BUNDLE` and runs `lib/conda_install_module.sh <id>`.
4. Wire the wrapper from `../setup/tab_data.toml`.

## User overrides

Edit `~/.config/open-genome/manifest.toml` - set `conda.conda_exe` to an absolute path if `conda` is not on default `PATH`. Legacy `paths.env` is imported once on bootstrap **only** when manifest path fields are still empty.
