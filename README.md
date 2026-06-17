# Open Genome

Terminal utility for genomics workflows, built on a Linutil-style Rust TUI: left pane categories, right pane actions, same keyboard model.

Open Genome helps privacy-minded users set up local genomics tooling, import sequencing files, prepare references, run a native Nextflow workflow, and generate evidence reports without uploading genome data.

## Install

Run the latest GitHub release:

```bash
curl -fsSL https://raw.githubusercontent.com/Jakeelamb/genome_os/main/start.sh | sh
```

Or clone and run from source:

```bash
git clone https://github.com/Jakeelamb/genome_os.git
cd genome_os
cargo run -p linutil_tui
```

## Run from source

```bash
cargo run -p linutil_tui
```

The TUI uses a built-in animated DNA logo by default and does not require a sibling checkout or private path dependency. Set `OPEN_GENOME_USE_PNG_LOGO=1` to use the bundled PNG fallback. The Nix package builds the same way: `nix build .#default`.

Release binary (workspace default):

```bash
cargo build --release -p linutil_tui
# target/release/linutil
```

### CLI flags

```bash
cargo run -p linutil_tui -- --help
```

Linutil-compatible options still apply: `--config`, `--theme`, `--skip-confirmation`, `--override-validation`, `--size-bypass`, `--mouse`, `--bypass-root`.

## First Run

1. Open `Setup -> Automated setup script` for the native guided path flow.
2. Choose the output/work folder with the file picker.
3. Optionally import sequencing files and choose an existing reference genome from the picker.
4. Run `Setup -> Install / update Open Genome tools` if the checklist shows missing tools.
5. Review `Setup -> Setup checklist` anytime; it is read-only.

## Configuration (manifest + conda)

- **User manifest:** `$XDG_CONFIG_HOME/open-genome/manifest.toml` (created on first Setup action from the bundled default).
- **Privacy:** local-only user data by default. Public tools, references, and pipelines may be downloaded; reads/BAMs/VCFs/logs are not uploaded.
- **Paths:** `paths.reference`, `paths.dataset`, `paths.workdir`, `paths.threads`.
- **Conda:** Open Genome can reuse an existing `conda`/`mamba` executable or install private Miniforge/Conda under `$XDG_DATA_HOME/open-genome/miniforge`.
- **Setup path selection:** The TUI uses a native file picker for setup paths, including the automated setup path flow. Direct shell use still falls back to `fzf` when available, or Bash/readline filesystem completion. Quoted or shell-escaped pasted paths are normalized. Selecting a sequencing file imports its containing folder so paired reads and related files are found together.
- **Setup checklist:** `Setup -> Setup checklist` is read-only. It shows completed and missing setup items, with the next action to run for each missing requirement.
- **Samples:** Setup can scan paired FASTQ/FASTQ.gz, existing BAM/CRAM, existing VCF, or user-provided assembly files, including mixed folders. It writes row-id based native Open Genome samplesheets.
- **Reference/workflow:** Genome Workflow actions fetch the public GATK GRCh38 bundle, index it locally, prepare the native Open Genome Nextflow pipeline, and run/resume it through the `opengenome` conda environment.
- **Reports:** The native workflow stages exact process outputs into the report compiler, then emits per-row HTML/TSV/JSON evidence with explicit limitations and PGx/annotation status. The base env includes lightweight `gfastats`; heavier report tools such as QUAST, VEP, and full PharmCAT installation are treated as optional/on-demand.
- **Environment:** `Setup -> Install / update Open Genome tools` is the single user-facing install action. It installs the main `opengenome` environment plus a small IGV environment because current GATK packages require Java 17 while current IGV requires Java 21.

## Safety Boundaries

Open Genome reports are evidence summaries, not diagnosis or treatment advice. Variant matches require review by classification, source date, review status, population frequency, phenotype, family history, and clinician judgment. Negative findings do not remove genetic risk.

See [docs/privacy-and-interpretation.md](docs/privacy-and-interpretation.md).

## Verification

```bash
scripts/check-genomics.sh
```

This runs the Python scanner/report tests, shell syntax checks, Rust tab metadata test, and a native Nextflow stub smoke test when Nextflow is available directly or through `conda run -n opengenome`.

Legacy `paths.env` is imported **once** on bootstrap only if the manifest path fields are still empty. Example templates: [examples/open-genome.manifest.toml](examples/open-genome.manifest.toml), [examples/open-genome.paths.env](examples/open-genome.paths.env).

**Requires Python 3.11+** on the machine that runs Setup scripts (`tomllib`). Conda installs need **conda** on `PATH` (or set `conda.conda_exe`).

## Linutil-style app config (`--config`)

Optional TOML for the TUI (auto-execute, confirmations, size bypass) — same schema as upstream Linutil. Example:

```toml
skip_confirmation = false
size_bypass = false
```

`auto_execute` matches **command titles** exactly as shown in the right-hand list.

## Upstream

Open Genome keeps the upstream TUI interaction model while replacing the command surface with local genomics workflows. The binary is still named `linutil` for compatibility with the inherited package layout.

## Docs

- [Privacy and interpretation boundaries](docs/privacy-and-interpretation.md)
- [Release checklist](docs/release-checklist.md)
- [Contributor notes](docs/contributor-notes.md)

## Contributing

See [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).
