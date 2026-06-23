# Contributor Notes

Open Genome is a local-first Rust TUI for genomics workflow setup, execution, and report review.

## Local Development

```bash
cargo run -p opengenome_tui
```

The main embedded workflow content lives under `core/tabs/`. User-facing setup scripts should keep prompts clear, local-first, and explicit about downloads.

Readiness/status checks should stay read-only. Use `core/tabs/open-genome/lib/setup_status.py` for setup state evaluation, and keep mutating behavior in explicit setup or workflow action scripts.

## Expected Checks

Run these before opening a pull request:

```bash
cargo fmt --check
cargo check -p opengenome_tui --all-features
cargo test
scripts/check-genomics.sh
```

## Contribution Scope

- Keep genomics data local by default.
- Prefer the existing `opengenome` conda environment over adding more separate environments.
- Preserve the TUI's existing navigation and keyboard controls unless the change explicitly targets interaction design.
- Include tests or smoke evidence for setup, scanning, pipeline, or report behavior changes.
