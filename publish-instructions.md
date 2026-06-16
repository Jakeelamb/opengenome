# Open Genome Publish Instructions

Use GitHub releases as the primary distribution path.

## Preflight

Run locally before publishing:

```bash
cargo fmt --check
cargo check -p linutil_tui --all-features
cargo test
scripts/check-genomics.sh
git diff --check
```

Confirm:

- `README.md` install and first-run instructions are current.
- `docs/release-checklist.md` matches the release flow.
- `.github/SECURITY.md` points to this repository.
- `start.sh` and `startdev.sh` download from `Jakeelamb/genome_os`.
- The release workflow has passed on `main`.

## Publish

1. Push `main`.
2. Run the `Open Genome Release` workflow manually.
3. Verify the release includes:
   - `linutil`
   - `linutil-aarch64`
   - `start.sh`
   - `startdev.sh`
4. Download `start.sh` from the release and smoke-test startup on a clean Linux VM.

The binary is still named `linutil` for compatibility with the inherited Rust package layout. Public release notes should call the product Open Genome.
