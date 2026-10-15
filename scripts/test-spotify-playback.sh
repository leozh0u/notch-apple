#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notch-spotify-playback.XXXXXX")"
trap 'rm -rf "$notch_test_dir"' EXIT
swiftc "$notch_root/boringNotch/models/SpotifyPlaybackRequest.swift" "$notch_root/Tests/SpotifyPlaybackChecks.swift" -o "$notch_test_dir/playback-checks"
"$notch_test_dir/playback-checks"
