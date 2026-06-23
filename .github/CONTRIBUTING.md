# Contributing to Open Genome

Open Genome is a local-first terminal app for personal genomics workflows. Contributions should keep setup clear, data local by default, and results explicit about their interpretation limits.

## Development Setup

```bash
git clone https://github.com/YOUR_USERNAME_HERE/opengenome.git
cd opengenome
cargo run -p opengenome_tui --bin opengenome
```

Setup scripts require Python 3.11+ for `tomllib`. Full workflow testing may also use conda, Java, Nextflow, and the bundled `opengenome` conda environment.

## Before Opening a Pull Request

Run:

```bash
cargo fmt --check
cargo check -p opengenome_tui --all-features
cargo test
scripts/check-genomics.sh
git diff --check
```

If a dependency is unavailable, mention the skipped check and the reason in the pull request.

## Contribution Guidelines

- Keep pull requests focused on one user-visible change, bug fix, or documentation update.
- Preserve the existing TUI controls and layout unless the change explicitly targets interaction design.
- Keep user genome data local by default. Be explicit when a script downloads public tools, references, or databases.
- Update README or `docs/` when changing setup, workflow, reporting, privacy, or release behavior.
- Do not submit generated code or LLM-assisted changes without reviewing, testing, and understanding them.

## License

By contributing, you agree that your contributions are licensed under the project's MIT license.
