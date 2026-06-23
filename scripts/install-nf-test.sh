#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=${NF_TEST_VERSION:-0.9.5}
tools_dir="$repo/.tools"
bin_dir="$tools_dir/bin"
home_dir="$tools_dir/nf-test-home"
archive_url="https://github.com/askimed/nf-test/releases/download/v${version}/nf-test-${version}.tar.gz"

mkdir -p "$bin_dir" "$home_dir"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fL "$archive_url" -o "$tmp/nf-test.tar.gz"
tar -xzf "$tmp/nf-test.tar.gz" -C "$tmp"

if ! test -f "$tmp/nf-test.jar"; then
	echo "nf-test archive did not contain nf-test.jar" >&2
	exit 1
fi
if ! test -f "$tmp/nf-test"; then
	echo "nf-test archive did not contain launcher" >&2
	exit 1
fi

install -m 0755 "$tmp/nf-test" "$bin_dir/nf-test"
install -m 0644 "$tmp/nf-test.jar" "$bin_dir/nf-test.jar"
mkdir -p "$home_dir/.nf-test"
install -m 0644 "$tmp/nf-test.jar" "$home_dir/.nf-test/nf-test.jar"

HOME="$home_dir" "$bin_dir/nf-test" version >/dev/null

echo "Installed nf-test $version:"
echo "  $bin_dir/nf-test"
