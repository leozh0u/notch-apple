#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notch-apple-tests.XXXXXX")"
trap 'rm -rf "$notch_test_dir"' EXIT
swiftc "$notch_root/boringNotch/models/FocusTimer.swift" "$notch_root/Tests/main.swift" -o "$notch_test_dir/countdown-tests"
"$notch_test_dir/countdown-tests"
