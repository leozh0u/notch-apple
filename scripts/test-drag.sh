#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notch-drag-tests.XXXXXX")"
trap 'rm -rf "$notch_test_dir"' EXIT
swiftc "$notch_root/boringNotch/observers/DragDetector.swift" \
    "$notch_root/Tests/DragActivationChecks.swift" -o "$notch_test_dir/drag-tests"
"$notch_test_dir/drag-tests"
