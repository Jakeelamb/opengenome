#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

if ! command -v nf-test >/dev/null 2>&1 && ! test -x "$repo/.tools/bin/nf-test"; then
	echo "== Install local nf-test =="
	bash scripts/install-nf-test.sh
fi

echo "== Genomics gate =="
scripts/check-genomics.sh

echo "== Real pipeline smoke =="
scripts/pipeline-real-smoke.sh

echo "== Rust formatting =="
cargo fmt --check

echo "== Rust package check =="
cargo check -p opengenome_tui --all-features

echo "== Rust workspace tests =="
cargo test --workspace --all-features

echo "== Whitespace/diff sanity =="
git diff --check

echo "== Process cleanup check =="
if pgrep -af 'nextflow|ttyd|opengenome_tui|target/debug/opengenome'; then
	echo "Unexpected helper process still running" >&2
	exit 1
fi

echo "ok - pipeline quality gate"
