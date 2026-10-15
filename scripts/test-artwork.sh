#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notch-artwork-tests.XXXXXX")"
trap 'rm -rf "$notch_test_dir"' EXIT
swiftc "$notch_root/boringNotch/extensions/NSImage+Extensions.swift" \
    "$notch_root/Tests/ArtworkChecks.swift" -o "$notch_test_dir/artwork-tests"
"$notch_test_dir/artwork-tests"
