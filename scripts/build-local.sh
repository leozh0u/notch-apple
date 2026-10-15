#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_build_dir="${NOTCH_APPLE_BUILD_DIR:-$notch_root/build}"
xcodebuild -project "$notch_root/boringNotch.xcodeproj" -scheme boringNotch \
  -configuration Debug -derivedDataPath "$notch_build_dir" CODE_SIGN_IDENTITY=- build
printf '\nApp: %s/Build/Products/Debug/Notch Apple.app\n' "$notch_build_dir"
