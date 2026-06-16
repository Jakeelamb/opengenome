# Open Genome

Terminal utility for genomics workflows, built on the [Linutil](https://github.com/ChrisTitusTech/linutil)-style Rust TUI: left pane categories, right pane actions, same keyboard model.

## Run from source

```bash
cargo run -p linutil_tui
```

The TUI uses the bundled PNG logo and does not require a sibling checkout or private path dependency. The Nix package builds the same way: `nix build .#default`.

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

## Configuration (manifest + conda)

- **User manifest:** `$XDG_CONFIG_HOME/open-genome/manifest.toml` (created on first Setup action from the bundled default).
- **Privacy:** local-only user data by default. Public tools, references, and pipelines may be downloaded; reads/BAMs/VCFs/logs are not uploaded.
- **Paths:** `paths.reference`, `paths.dataset`, `paths.workdir`, `paths.threads`.
- **Conda:** Open Genome can install private Miniforge/Conda under `$XDG_DATA_HOME/open-genome/miniforge`, or use `conda.conda_exe`.
- **Samples:** Setup can scan paired FASTQ/FASTQ.gz, existing BAM/CRAM, existing VCF, or user-provided assembly files, including mixed folders. It writes row-id based native Open Genome samplesheets plus a Sarek-compatible sheet for the advanced external workflow.
- **Reference/workflow:** Assembly actions fetch the public GATK GRCh38 bundle, index it locally, prepare the native Open Genome Nextflow pipeline, and run/resume it through the single `opengenome` conda environment. Sarek remains available as an advanced external workflow.
- **Reports:** The native workflow stages exact process outputs into the report compiler, then emits per-row HTML/TSV/JSON evidence with explicit limitations and PGx/annotation status. The base env includes lightweight `gfastats`; heavier report tools such as QUAST, VEP, and full PharmCAT installation are treated as optional/on-demand.
- **Environment:** the main `opengenome` conda spec lives at [core/tabs/open-genome/modules/opengenome/environment.yml](core/tabs/open-genome/modules/opengenome/environment.yml). It is the source of truth for fresh core installs. IGV is kept in the separate `og-genome-browser` module because current GATK packages require Java 17 while current IGV requires Java 21. Legacy per-tool module specs remain under [core/tabs/open-genome/modules/](core/tabs/open-genome/modules/) for fallback/debugging.

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

Forked from Chris Titus Tech’s Linutil; see upstream README and license in `LICENSE`. Contributor graphics and distro install snippets in older revisions referred to Linutil releases.

## Contributing

See [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).
