#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notch-shelf-tests.XXXXXX")"
trap 'rm -rf "$notch_test_dir"' EXIT
swiftc \
    "$notch_root/boringNotch/components/Shelf/Services/ShelfDropService.swift" \
    "$notch_root/boringNotch/components/Shelf/Services/TemporaryFileStorageService.swift" \
    "$notch_root/boringNotch/components/Shelf/Models/Bookmark.swift" \
    "$notch_root/boringNotch/components/Shelf/Models/ShelfItem.swift" \
    "$notch_root/boringNotch/extensions/NSItemProvider+LoadHelpers.swift" \
    "$notch_root/boringNotch/extensions/URL+SecurityScoped.swift" \
    "$notch_root/Tests/ShelfDropChecks.swift" -o "$notch_test_dir/shelf-tests"
"$notch_test_dir/shelf-tests"
