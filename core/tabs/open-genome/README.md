# Open Genome bundle (modular)

This directory is embedded next to the tab trees and extracted at runtime with the TUI.

## Layout

| Path | Role |
|------|------|
| `manifest.default.toml` | Shipped defaults for local paths, privacy, sample import, GRCh38 resources, native workflow state, cache paths, results, and module toggles. Copied to `~/.config/open-genome/manifest.toml` on first use. |
| `lib/manifest_cli.py` | Read/write manifest (Python 3.11+ `tomllib`). |
| `lib/sample_scan.py` | Scan a local sequencing folder and emit Open Genome samplesheets. |
| `lib/report_compiler.py` | Compile pipeline outputs into `report_index.html`, compatibility HTML, TSV findings, and JSON evidence artifacts. |
| `pipelines/open-genome/` | Native Nextflow DSL2 reference-germline pipeline for Illumina WGS, PacBio HiFi, ONT, BAM, and CRAM inputs. |
| `pipelines/vcf-annotate/` | Report-only Nextflow DSL2 pipeline for existing VCF inputs. |
| `pipelines/denovo-assembly/` | Separate Nextflow DSL2 pipeline for hifiasm, Flye, and Verkko long-read de novo assembly. |
| `pipelines/pipeline-contract.md` | Outcome split, preset names, and stable report ABI for the TUI. |
| `lib/conda_resolve.sh` | Pick `conda` from manifest + PATH, with explicit override support. |
| `lib/conda_install_module.sh` | `conda env create` / `env update` from a module `environment.yml`, with optional explicit-lock support when a maintained lock file exists. |
| `modules/<id>/module.toml` | Human metadata (`id`, `display_name`, `description`). |
| `modules/<id>/environment.yml` | Conda spec: `name:` becomes the env name; channels + packages. |
| `modules/<id>/environment.lock.*.txt` | Optional explicit conda lock for matching platforms when maintained for that module. |

## V1 local WGS flow

1. Start Here -> Start guided setup.
2. Start Here -> Check what is ready to see what is configured and what still needs attention.
3. Start Here -> Try sample data if you want to generate tiny local demo files plus reference variant, existing VCF, and de novo assembly preview outputs without using private genome files. The preview includes fastp/FastQC/MultiQC-style QC artifacts, read-density plots, assembly FASTA/GFA, circularity review, graph preview, assembly summary TSV, and assembly manifest JSON.
4. Start Here -> Run human validation dataset if you want public human data to exercise the reference germline, existing VCF, and de novo assembly pipeline entrypoints. The default is GIAB HG003 PacBio HiFi chr20 downsampled to 10x; set `OPEN_GENOME_HUMAN_VALIDATION_TARGET_COVERAGE=5` or `10`, and set `OPEN_GENOME_RERUN_HUMAN_VALIDATION=1` only when recomputing.
5. Run Analysis -> Run reference-based analysis, Run existing VCF report, or Run de novo assembly. Each action prepares its command file automatically if needed.
6. Results -> Open my report or Results -> Explain my results.
7. Results -> Understand report limits before interpreting findings.

Open Genome may download public tools and reference resources, but user reads, BAM/CRAM, VCF, logs, and metadata stay local.

The native report links FastQC/fastp/MultiQC files, summarizes mosdepth depth and breadth, renders a chromosome coverage chart, separates SNP/indel/mtDNA variant counts, reads VEP `CSQ` or SnpEff `ANN` consequence fields when present, lists local ClinVar/dbSNP/gnomAD evidence, separates PharmCAT PGx status from disease-variant evidence, and writes a reference-guided mitochondrial consensus FASTA when chrM/MT is present. gnomAD, VEP/SnpEff, and PharmCAT are optional local-cache inputs; if they are not configured, the report marks those sections as skipped instead of calling an external service.

## De novo assembly flow

1. Start Here -> Start guided setup with a folder containing long-read files named with `hifi`, `ccs`, `pacbio`, `revio`, `ont`, `nanopore`, or `ultralong`.
2. Run Analysis -> Run de novo assembly. It prepares the long-read assembly command automatically if needed.
3. Results -> Open my report opens the latest de novo assembly report after the run completes.

The reference workflow supports Illumina WGS through BWA-MEM2/BWA and GATK, PacBio HiFi reference alignment through pbmm2 or minimap2 `map-hifi`, ONT reference alignment through minimap2 `map-ont` or Dorado aligner when installed, and Clair3 model selection for PacBio/ONT local long-read variant calling. This is a platform-specific default split: GATK remains the Illumina short-read default, while Clair3 is the long-read default. DeepVariant remains an explicit external caller for users with a compatible install or container wrapper. Clair3 rationale: Zheng et al., [Symphonizing pileup and full-alignment for deep learning-based long-read variant calling](https://doi.org/10.1038/s43588-022-00387-x), Nature Computational Science 2022; Zheng et al., [Accelerated long-read variant calling with Clair3 for whole-genome sequencing](https://doi.org/10.1093/bioinformatics/btag181), Bioinformatics 2026.

The de novo workflow writes primary contig FASTA/GFA outputs, read stats, assembler logs, gfastats output, `denovo_assembly_summary.tsv`, `denovo_assembly_manifest.json`, and `denovo_assembly_report.html`. The bundled preview also includes circularity and read-density review artifacts so users can inspect the public-facing report shape without running a human-scale assembly. It defaults to hifiasm for HiFi/CCS reads, Flye for ONT-only reads, and keeps Verkko available for high-end accurate-long-read plus ultra-long ONT assembly once separate read streams are available.

Run `scripts/pipeline-quality-gate.sh` from the repo root before publishing. It installs local `nf-test` into `.tools/` when needed, then runs the genomics gate, Rust workspace tests, whitespace checks, and leftover-process checks.

For focused workflow iteration, run `scripts/check-genomics.sh`. It verifies Python scanner/report tests, shell helper tests, shell syntax, Rust tab metadata, pipeline contract validation, `nf-test` pipeline contract tests when available, and the native/reference plus de novo Nextflow stub graphs, including PacBio/Clair3 reference mode and Flye/Verkko de novo branches.

For non-stub workflow proof, run `scripts/pipeline-real-smoke.sh`. It uses tiny synthetic local data to execute the existing-VCF report workflow and the default Illumina reference workflow with actual tools when the `opengenome` conda environment is installed. It also runs real PacBio HiFi Clair3 and ONT Clair3 reference calls against bounded official Clair3 demo fixtures. When `opengenome-denovo` is installed, it runs a direct Flye assembly-stage smoke against Flye's bundled raw-read E. coli 500 kb fixture and runs the hifiasm Nextflow report path against Flye's bundled HiFi fixture.

## Adding tools

1. Prefer adding packages to `modules/opengenome/environment.yml`.
2. Keep the user-facing Start Here tab focused on the guided path; move manual tool actions behind Advanced manual setup.
3. Create a separate `modules/<id>/` environment only when dependency conflicts or tool weight make that useful, as with IGV's Java 21 requirement and hifiasm de novo assembly.

## User overrides

Edit `~/.config/open-genome/manifest.toml` - set `conda.conda_exe` to an absolute path if `conda` is not on default `PATH`. Legacy `paths.env` is imported once on bootstrap **only** when manifest path fields are still empty.
