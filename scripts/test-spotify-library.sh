#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notch-spotify-tests.XXXXXX")"
trap 'rm -rf "$notch_test_dir"' EXIT
swiftc -D SPOTIFY_KEYCHAIN_TESTING "$notch_root/boringNotch/managers/SpotifyAuthorization.swift" \
    "$notch_root/boringNotch/managers/SpotifyLibrary.swift" \
    "$notch_root/Tests/SpotifyLibraryChecks.swift" -o "$notch_test_dir/spotify-checks"
"$notch_test_dir/spotify-checks"
