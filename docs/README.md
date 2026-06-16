# Open Genome Docs

Open Genome is a local-first terminal app for setting up and running personal genomics workflows. These docs are intentionally small until the project has a hosted documentation site.

## Start Here

- [Privacy and interpretation boundaries](privacy-and-interpretation.md)
- [Release checklist](release-checklist.md)
- [Contributor notes](contributor-notes.md)

## Local Verification

Run the same checks used before release:

```bash
cargo fmt --check
cargo check -p linutil_tui --all-features
cargo test
scripts/check-genomics.sh
```

`scripts/check-genomics.sh` covers Python scanner/report tests, shell syntax, Rust tab metadata, and a native Nextflow stub smoke test when Nextflow is available.
