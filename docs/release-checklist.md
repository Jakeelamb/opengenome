# Release Checklist

Use this checklist before publishing a GitHub release.

## Repository

- README describes the current product and install path.
- GitHub issue templates, security policy, and pull request template point to this repository.
- No stale upstream Linutil docs, badges, domains, or release links remain in release-facing files.
- `Setup -> Setup checklist` gives a clear readiness status for new users.

## Verification

```bash
cargo fmt --check
cargo check -p linutil_tui --all-features
cargo test
scripts/check-genomics.sh
git diff --check
```

## Release Build

Use the GitHub release workflow from `main`. It builds Linux x86_64 and aarch64 binaries and attaches `start.sh` plus `startdev.sh`.

The binary name is still `linutil` for compatibility with the upstream TUI package layout. The public project name and release text should use Open Genome.

## Manual Smoke

1. Run the TUI from source: `cargo run -p linutil_tui`.
2. Open `Setup -> Setup checklist`.
3. Choose an output folder.
4. Choose or import a small sequencing test folder.
5. Confirm the checklist updates as expected.
