#!/usr/bin/env bash
# Purpose: Build a standalone Android release APK with the embedded RN JS bundle
#          (no Metro/dev-server required at runtime), for distribution via download/email.
# Author: AuBackup team
# Created: 2026-08-03
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"

VERSION_NAME="$(grep -o 'versionName "[^"]*"' "$ANDROID_DIR/app/build.gradle" | head -1 | sed -E 's/versionName "([^"]*)"/\1/')"
OUTPUT_DIR="$PROJECT_ROOT/dist"
VERIFY_BUNDLE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --no-verify)
      VERIFY_BUNDLE=false
      shift
      ;;
    --help|-h)
      cat <<EOF
Usage: bash scripts/build_release_apk.sh [--output-dir <dir>] [--no-verify]

Build a standalone Android release APK with the embedded RN JS bundle. The APK
is signed with the debug keystore and runs without Metro, so it can be
distributed directly (e.g. emailed) and installed from "unknown sources".

Options:
  --output-dir <dir>  Copy the built APK to <dir> (default: $PROJECT_ROOT/dist).
  --no-verify         Skip verifying that the JS bundle asset is embedded.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

require_cmd node
require_cmd java

echo "Building release APK (embedded JS bundle) for $ANDROID_APP_ID..."
(
  cd "$ANDROID_DIR"
  ./gradlew assembleRelease
)

RELEASE_APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
if [[ ! -f "$RELEASE_APK" ]]; then
  echo "Release APK was not produced at $RELEASE_APK" >&2
  exit 1
fi

if [[ "$VERIFY_BUNDLE" == true ]]; then
  if ! unzip -l "$RELEASE_APK" 2>/dev/null | grep "assets/index.android.bundle" >/dev/null; then
    echo "Built APK does not contain the JS bundle asset (assets/index.android.bundle)." >&2
    exit 1
  fi
  echo "Verified: APK contains assets/index.android.bundle"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
APK_NAME="AuBackup-${VERSION_NAME:-1.0.0}-release-${TIMESTAMP}.apk"
mkdir -p "$OUTPUT_DIR"
cp "$RELEASE_APK" "$OUTPUT_DIR/$APK_NAME"
echo ""
echo "Release APK ready: $OUTPUT_DIR/$APK_NAME"
echo ""
echo "Distribute the APK via email/download. To install on a device:"
echo "  - Allow 'Install unknown apps' for the app you use to open the APK, or"
echo "  - Connect the device and run: adb install \"$OUTPUT_DIR/$APK_NAME\""
