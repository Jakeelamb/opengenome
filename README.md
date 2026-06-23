# Open Genome

Terminal utility for local genomics workflows: left pane workflow areas, right pane actions, keyboard-first navigation.

Open Genome helps privacy-minded users set up local genomics tooling, import sequencing files, prepare references, run native Nextflow workflows, assemble long-read genomes de novo, and generate evidence reports without uploading genome data.

![Open Genome terminal interface showing the welcome actions and setup checklist](https://raw.githubusercontent.com/Jakeelamb/opengenome/main/docs/assets/open-genome-tui.png)

## Install

Run the latest GitHub release:

```bash
curl -fsSL https://raw.githubusercontent.com/Jakeelamb/opengenome/main/start.sh | sh
```

Or clone and run from source:

```bash
git clone https://github.com/Jakeelamb/opengenome.git
cd opengenome
cargo run -p opengenome_tui
```

## Run from source

```bash
cargo run -p opengenome_tui
```

The TUI uses a built-in animated DNA logo by default and does not require a sibling checkout or private path dependency. Set `OPEN_GENOME_USE_PNG_LOGO=1` to use the bundled PNG fallback. The Nix package builds the same way: `nix build .#default`.

Release binary (workspace default):

```bash
cargo build --release -p opengenome_tui
# target/release/opengenome
```

### CLI flags

```bash
cargo run -p opengenome_tui -- --help
```

App options include `--config`, `--theme`, `--skip-confirmation`, `--override-validation`, `--size-bypass`, `--mouse`, and `--bypass-root`.

Generate the bundled demo output bundle without launching the TUI:

```bash
cargo run -p opengenome_tui -- --demo-output
```

Use this in non-interactive terminals, CI logs, or command runners that cannot draw a terminal UI.
It creates the same tiny local preview bundle as `Start Here -> Try sample data`: reference-germline and existing-VCF HTML reports, fastp JSON/HTML, FastQC HTML, MultiQC placeholders, read-density SVG plots, de novo assembly FASTA/GFA, circularity review TSV, assembly graph preview, gfastats metrics, `denovo_assembly_summary.tsv`, and `denovo_assembly_manifest.json`.

Run the public human validation dataset without launching the TUI:

```bash
cargo run -p opengenome_tui -- --human-validation-output
```

This downloads public GIAB HG003 PacBio HiFi chr20 data, downsamples the bounded region to 10x by default, runs the reference germline, existing VCF, and de novo assembly pipeline entrypoints, then keeps outputs under the Open Genome work folder for reload. Set `OPEN_GENOME_HUMAN_VALIDATION_TARGET_COVERAGE=5` or `10` to choose the target, and set `OPEN_GENOME_RERUN_HUMAN_VALIDATION=1` only when you want to recompute instead of reloading existing outputs.

## First Run

1. Open `Welcome -> About Open Genome` for the local-first project summary and expectations.
2. Open `Start Here -> Start guided setup`.
3. Choose where results stay and select sequencing files with the native picker.
4. Watch the persistent setup checklist below the main action pane for saved conda, sequencing, output, CPU/core limit, samplesheet, recommended analysis plan, reference, and report paths.
5. Use `Start Here -> Check what is ready` anytime; it is read-only.
6. Run locally with `Run Analysis -> Run reference-based analysis`, `Run Analysis -> Run existing VCF report`, or `Run Analysis -> Run de novo assembly`.
7. Review results with `Results -> Open my report` or `Results -> Explain my results`.

## Configuration (manifest + conda)

- **User manifest:** `$XDG_CONFIG_HOME/open-genome/manifest.toml` (created on first Setup action from the bundled default).
- **Privacy:** local-only user data by default. Public tools, references, and pipelines may be downloaded; reads/BAMs/VCFs/logs are not uploaded.
- **Paths:** `paths.reference`, `paths.dataset`, `paths.workdir`, `paths.threads`.
- **Conda:** Open Genome can reuse an existing `conda`/`mamba` executable or install private Miniforge/Conda under `$XDG_DATA_HOME/open-genome/miniforge`.
- **Setup path selection:** The TUI uses a native file picker for setup paths, including the automated setup path flow. Direct shell use still falls back to `fzf` when available, or Bash/readline filesystem completion. Quoted or shell-escaped pasted paths are normalized. Selecting a sequencing file imports its containing folder so paired reads and related files are found together.
- **Persistent checklist:** The TUI keeps a compact setup checklist below the main action pane. It reads the local manifest, samplesheet, and PATH to show conda, sequencing, output, CPU/core limit, samplesheet, recommended analysis plan, reference, and report status while you work.
- **Setup readiness:** `Start Here -> Check what is ready` is read-only. It shows completed and missing setup items, with the next action to run for each missing requirement.
- **Samples:** Setup can scan paired FASTQ/FASTQ.gz, long-read FASTQ/BAM, existing BAM/CRAM, existing VCF, or user-provided assembly files, including mixed folders. Run preparation selects one outcome: reference germline analysis, existing-VCF reporting, or de novo assembly. Long-read inputs are detected conservatively from file names containing markers such as `hifi`, `ccs`, `pacbio`, `revio`, `ont`, `nanopore`, or `ultralong`.
- **Sample dataset:** `Start Here -> Try sample data` generates tiny local demo files plus preview outputs for the reference germline, existing VCF, and de novo assembly workflows without using private data, downloads, or heavy workflow runs. The preview includes fastp/FastQC/MultiQC-style QC artifacts, read-density plots, de novo assembly FASTA/GFA, circularity review, graph preview, assembly summary TSV, and assembly manifest JSON.
- **Human validation dataset:** `Start Here -> Run human validation dataset` downloads public GIAB HG003 PacBio HiFi chr20 data, downsamples the bounded region to the requested target coverage, runs the reference germline, existing VCF, and de novo assembly pipeline entrypoints, and records the output folders in the manifest. Reopening the action reloads existing outputs unless `OPEN_GENOME_RERUN_HUMAN_VALIDATION=1` is set.
- **Reference/workflow:** `Start Here` owns setup and readiness. `Run Analysis -> Run reference-based analysis` aligns reads or uses BAM/CRAM, runs QC, calls variants, and builds a report through the `opengenome` conda environment. `Run Analysis -> Run existing VCF report` normalizes and summarizes a VCF without alignment or variant calling. `Run Analysis -> Run de novo assembly` assembles PacBio HiFi/CCS or Oxford Nanopore reads into contigs and assembly review outputs. Manual reference and command steps live under advanced folders.
- **Variant calling:** Illumina auto mode uses GATK. PacBio HiFi and ONT auto modes use Clair3 with platform-specific model directories. This is a data-type split, not a claim that Clair3 replaces GATK: GATK is the short-read default, while Clair3 is the long-read default. DeepVariant remains an explicit external executable integration for users who provide a compatible install or container wrapper.
- **Recommended defaults:** If you are not sure which tools to choose, keep the TUI defaults. Paired Illumina WGS uses BWA-MEM2 plus GATK. PacBio HiFi/CCS reference runs use pbmm2 plus Clair3, and ONT reference runs use minimap2 plus Clair3. Existing VCFs use the report-only workflow. HiFi de novo assembly uses hifiasm, and ONT-only de novo assembly uses Flye.
- **De novo assembly:** `Run Analysis -> Run de novo assembly` uses the separate `opengenome-denovo` environment and does not require a reference FASTA. The workflow supports hifiasm for HiFi, Flye for ONT-only reads, and Verkko for high-end T2T-style accurate-long-read plus ultra-long ONT assembly once separate read streams are available. Human-scale assembly can require substantial RAM, CPU, and scratch disk; set `OPEN_GENOME_DENOVO_MEMORY` before preparing the command to override the default memory request.
- **Reports:** The native workflow emits `report_index.html` plus compatibility `open_genome_report.html`, TSV findings, JSON evidence, and a run manifest. The report links FastQC/fastp/MultiQC files, shows mosdepth depth and breadth charts, separates SNP/indel/mtDNA variant counts, summarizes VEP `CSQ` or SnpEff `ANN` consequence fields when present, lists local ClinVar/dbSNP/gnomAD evidence, keeps PharmCAT PGx status in its own section, and builds a reference-guided mitochondrial consensus FASTA when chrM/MT is available. Use `Start Here -> Load existing results` when results already exist on disk, then `Results -> Open my report` or `Results -> Explain my results` without rerunning.
- **Assembly reports:** The de novo workflow emits `denovo_assembly_report.html`, `denovo_assembly_summary.tsv`, `denovo_assembly_manifest.json`, primary contigs FASTA/GFA, read stats, assembler logs, and gfastats output. The bundled preview also shows circularity and read-density review artifacts so users can inspect the intended public report shape before running a heavy assembly. The report surfaces assembler, platform, contig count, total assembled bases, N50, and longest contig.
- **Optional public evidence:** ClinVar, dbSNP, gnomAD, VEP/SnpEff, and PharmCAT are local-cache driven. Open Genome does not upload variants for annotation, and skipped report sections mean the matching local resource or VCF annotation field was not configured.
- **Environment:** `Start Here -> Advanced manual setup -> Install or update local tools` installs the main `opengenome` environment, the separate `opengenome-denovo` assembly environment, and a small IGV environment because current GATK packages require Java 17 while current IGV requires Java 21.
- **Learn More:** The `Learn More` tab lists current human reference sources, workflow-compatible GRCh38 bundles, T2T-CHM13 resources, Conda/Bioconda links, and source/paper links for the tools Open Genome uses.

## Tool Rationale

- **GATK for Illumina:** Open Genome keeps GATK HaplotypeCaller as the default short-read germline caller because it is the established Broad Best Practices path for Illumina SNP/indel discovery.
- **Clair3 for PacBio/ONT:** Open Genome uses Clair3 for long-read germline small variants because Clair3 is designed around long-read error profiles with pileup plus full-alignment models. The core paper is Zheng et al., [Symphonizing pileup and full-alignment for deep learning-based long-read variant calling](https://doi.org/10.1038/s43588-022-00387-x), Nature Computational Science 2022. A newer acceleration paper is Zheng et al., [Accelerated long-read variant calling with Clair3 for whole-genome sequencing](https://doi.org/10.1093/bioinformatics/btag181), Bioinformatics 2026.

## Safety Boundaries

Open Genome reports are evidence summaries, not diagnosis or treatment advice. Variant matches require review by classification, source date, review status, population frequency, phenotype, family history, and clinician judgment. Negative findings do not remove genetic risk.

Mitochondrial output is a technical mtDNA coverage/variant/consensus summary. It is not de novo mtDNA assembly, heteroplasmy validation, haplogroup assignment, or medical interpretation.

See [docs/privacy-and-interpretation.md](docs/privacy-and-interpretation.md).

## Verification

Full local release gate:

```bash
scripts/pipeline-quality-gate.sh
```

This installs a project-local `nf-test` under `.tools/` when needed, runs the genomics gate, runs the Rust workspace tests, checks whitespace, and verifies no local helper processes were left running.

The full gate also runs a tiny real-tool smoke when the local conda environments are available. That smoke executes the existing-VCF report workflow and the default Illumina reference workflow with actual Nextflow tasks, BWA-MEM2, GATK, bcftools, mosdepth, MultiQC, and the report compiler. With long-read tooling installed, it also runs bounded Clair3 PacBio/ONT calls, a direct Flye assembly-stage check, and a hifiasm Nextflow report-contract check.

Install only the local Nextflow test runner:

```bash
scripts/install-nf-test.sh
```

Focused genomics gate:

```bash
scripts/check-genomics.sh
```

This runs the Python scanner/report tests, shell helper tests, shell syntax checks, Rust tab metadata test, pipeline contract validation, `nf-test` pipeline contract tests when installed, native/reference plus de novo Nextflow stub smoke tests, and tiny real-tool smoke tests when the local conda environments are installed.

Real-tool pipeline smoke only:

```bash
scripts/pipeline-real-smoke.sh
```

Legacy `paths.env` is imported **once** on bootstrap only if the manifest path fields are still empty. Example templates: [examples/open-genome.manifest.toml](examples/open-genome.manifest.toml), [examples/open-genome.paths.env](examples/open-genome.paths.env).

**Requires Python 3.11+** on the machine that runs Setup scripts (`tomllib`). Conda installs need **conda** on `PATH` (or set `conda.conda_exe`).

## App config (`--config`)

Optional TOML for the TUI: auto-execute, confirmations, and size bypass. Example:

```toml
skip_confirmation = false
size_bypass = false
```

`auto_execute` matches **command titles** exactly as shown in the right-hand list.

## Docs

- [Privacy and interpretation boundaries](docs/privacy-and-interpretation.md)
- [Release checklist](docs/release-checklist.md)
- [Contributor notes](docs/contributor-notes.md)

## Contributing

See [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).
