#!/bin/bash
set -euo pipefail
notch_root="$(cd "$(dirname "$0")/.." && pwd)"
notch_build_dir="${NOTCH_APPLE_BUILD_DIR:-$notch_root/build}"
notch_configuration="${NOTCH_APPLE_CONFIGURATION:-Release}"
xcodebuild -project "$notch_root/boringNotch.xcodeproj" -scheme boringNotch \
  -configuration "$notch_configuration" -derivedDataPath "$notch_build_dir" \
  CODE_SIGN_IDENTITY=- SWIFT_OPTIMIZATION_LEVEL=-Osize build
python3 "$notch_root/scripts/sign-preview.py" "$notch_build_dir/Build/Products/$notch_configuration/Notch Apple.app"
printf '\nApp: %s/Build/Products/%s/Notch Apple.app\n' "$notch_build_dir" "$notch_configuration"
