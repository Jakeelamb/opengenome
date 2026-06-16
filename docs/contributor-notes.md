# Contributor Notes

Open Genome inherits a Rust TUI structure from Linutil but the user-facing product is a local-first genomics workflow launcher.

## Local Development

```bash
cargo run -p linutil_tui
```

The main embedded workflow content lives under `core/tabs/`. User-facing setup scripts should keep prompts clear, local-first, and explicit about downloads.

## Expected Checks

Run these before opening a pull request:

```bash
cargo fmt --check
cargo check -p linutil_tui --all-features
cargo test
scripts/check-genomics.sh
```

## Contribution Scope

- Keep genomics data local by default.
- Prefer the existing `opengenome` conda environment over adding more separate environments.
- Preserve the TUI's existing navigation and keyboard controls unless the change explicitly targets interaction design.
- Include tests or smoke evidence for setup, scanning, pipeline, or report behavior changes.
