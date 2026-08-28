#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"

SERIAL=""
GRADLE_TASK="installDebug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      ;;
    --serial)
      SERIAL="${2:-}"
      shift 2
      ;;
    --assemble-only)
      GRADLE_TASK="assembleDebug"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash scripts/android_device_build.sh [--serial <device-serial>] [--assemble-only]

Build and install (or only assemble) the Android debug app for a physical device.

Options:
  --serial <device-serial>  Target adb serial; required when multiple devices are connected.
  --assemble-only           Build APK only (no install).
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

require_cmd adb

TARGET_SERIAL="$(resolve_device_serial "$SERIAL")"
assert_device_online "$TARGET_SERIAL"

echo "Using Android device: $TARGET_SERIAL"
echo "Running Gradle task: $GRADLE_TASK"

(
  cd "$ANDROID_DIR"
  ANDROID_SERIAL="$TARGET_SERIAL" ./gradlew "$GRADLE_TASK"
)

if [[ "$GRADLE_TASK" == "installDebug" ]]; then
  echo "Debug app installed on $TARGET_SERIAL."
fi
