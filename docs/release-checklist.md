# Release Checklist

Use this checklist before publishing a GitHub release.

## Repository

- README describes the current product and install path.
- GitHub issue templates, security policy, and pull request template point to this repository.
- No stale upstream fork docs, badges, domains, or release links remain in release-facing files.
- `Start Here -> Check what is ready` gives a clear read-only readiness status for new users.
- `Start Here -> Try sample data` generates tiny local demo files plus reference variant, existing VCF, and de novo assembly preview outputs without requiring downloads.
- `Start Here -> Run human validation dataset` runs public GIAB HG003 chr20 HiFi data through the reference germline, existing VCF, and de novo assembly pipeline entrypoints, then reloads existing outputs on the next run.
- The Welcome tab opens read-only project/about/support text without a confirmation prompt.
- The persistent setup checklist shows conda, sequencing, output, samplesheet, reference, and report status below the main action pane.
- `docs/pipeline-matrix.md` matches the published Nextflow modes, conda environments, and smoke-test coverage.

## Verification

```bash
scripts/pipeline-quality-gate.sh
```

The gate installs local `nf-test` into `.tools/` if needed, runs `scripts/check-genomics.sh`, runs Rust workspace tests, checks whitespace, and fails if local helper processes are still running.

It also runs `scripts/pipeline-real-smoke.sh` when the local conda environments are installed, covering tiny non-stub existing-VCF, Illumina/GATK, PacBio HiFi/Clair3, ONT/Clair3, direct Flye assembly-stage, and hifiasm Nextflow report-contract checks with real tool execution.

Focused commands:

```bash
cargo fmt --check
cargo check -p opengenome_tui --all-features
cargo test
scripts/check-genomics.sh
scripts/pipeline-real-smoke.sh
git diff --check
```

## Release Build

Use the GitHub release workflow from `main`. It builds Linux x86_64 and aarch64 binaries and attaches `start.sh` plus `startdev.sh`.

The binary name is `opengenome`. The public project name and release text should use Open Genome.

## Manual Smoke

1. Run the TUI from source: `cargo run -p opengenome_tui`.
2. Open `Start Here -> Check what is ready`.
3. Choose an output/work folder.
4. Run `Start Here -> Try sample data`.
5. Confirm the checklist and Results tab show the generated demo output index and de novo assembly report.
6. Confirm `Results -> Explain my results` counts fastp outputs, FastQC reports, read-density plots, assembly FASTA/GFA, circularity tables, and graph previews.
7. Run `cargo run -p opengenome_tui -- --human-validation-output`.
8. Confirm it reports public HG003 chr20 data, a downsampled target coverage, reference germline output, existing VCF output, de novo assembly output, and reloads without recomputing on a second run.
