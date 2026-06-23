# Open Genome Docs

Open Genome is a local-first terminal app for setting up and running personal genomics workflows. These docs are intentionally small until the project has a hosted documentation site.

## Start Here

- [Privacy and interpretation boundaries](privacy-and-interpretation.md)
- [Pipeline matrix](pipeline-matrix.md)
- [Release checklist](release-checklist.md)
- [Contributor notes](contributor-notes.md)

## Local Verification

Run the same checks used before release:

```bash
scripts/pipeline-quality-gate.sh
```

For focused iteration:

```bash
cargo fmt --check
cargo check -p opengenome_tui --all-features
cargo test
scripts/check-genomics.sh
```

`scripts/pipeline-quality-gate.sh` installs project-local `nf-test` under `.tools/` when needed, then runs the genomics gate, Rust workspace tests, whitespace checks, and a leftover-process check.

`scripts/check-genomics.sh` covers Python scanner/report tests, shell helper tests, shell syntax, Rust tab metadata, pipeline contract validation, `nf-test` pipeline contract tests when available, and native/reference plus de novo Nextflow stub smoke tests when Nextflow is available, including PacBio/Clair3 reference mode and Flye/Verkko de novo branches.

`scripts/pipeline-real-smoke.sh` runs tiny non-stub workflows through the local conda environments when available. It verifies the existing-VCF report workflow, default Illumina reference workflow, PacBio HiFi/Clair3 and ONT/Clair3 reference workflows, plus a direct Flye assembly-stage smoke and the hifiasm Nextflow report path with actual tool execution and report output checks.

The guided setup explains each step before changing anything. The Start Here tab keeps the default path small and moves manual conda/reference controls behind Advanced manual setup. Long-read de novo assembly is exposed as a separate Run Analysis action and uses its own `opengenome-denovo` conda environment.

The TUI opens with a Welcome tab for the project summary, expected workflow, and support notes. A persistent setup checklist sits below the main action pane and shows the saved conda, sequencing, output, CPU/core limit, samplesheet, recommended analysis plan, reference, and report paths from the local manifest and samplesheet.
