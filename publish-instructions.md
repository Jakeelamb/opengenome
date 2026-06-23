# Open Genome Publish Instructions

Use GitHub releases as the primary distribution path.

## Preflight

Run locally before publishing:

```bash
scripts/pipeline-quality-gate.sh
```

Confirm:

- `README.md` install and first-run instructions are current.
- `docs/release-checklist.md` matches the release flow.
- `.github/SECURITY.md` points to this repository.
- `start.sh` and `startdev.sh` download from `Jakeelamb/opengenome`.
- The release workflow has passed on `main`.

## Publish

1. Push `main`.
2. Run the `Open Genome Release` workflow manually.
3. Verify the release includes:
   - `opengenome`
   - `opengenome-aarch64`
   - `start.sh`
   - `startdev.sh`
4. Download `start.sh` from the release and smoke-test startup on a clean Linux VM.

Public release notes should call the product Open Genome.
