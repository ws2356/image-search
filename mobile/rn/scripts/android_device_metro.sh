#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"

SERIAL=""
EXTRA_EXPO_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      SERIAL="${2:-}"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash scripts/android_device_metro.sh [--serial <device-serial>] [-- <extra expo args...>]

Set up adb reverse for Metro and start Expo dev server for dev-client.

Examples:
  bash scripts/android_device_metro.sh
  bash scripts/android_device_metro.sh --serial R58M1234567
  bash scripts/android_device_metro.sh -- --clear
EOF
      exit 0
      ;;
    --)
      shift
      if [[ $# -eq 0 ]]; then
        break
      fi
      case "${1:-}" in
        --serial|--help|-h)
          ;;
        *)
          EXTRA_EXPO_ARGS=("$@")
          break
          ;;
      esac
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

require_cmd adb
require_cmd pnpm

TARGET_SERIAL="$(resolve_device_serial "$SERIAL")"
assert_device_online "$TARGET_SERIAL"

echo "Using Android device: $TARGET_SERIAL"
echo "Configuring adb reverse for Metro (8081)..."
setup_adb_reverse "$TARGET_SERIAL"

cd "$PROJECT_ROOT"
exec pnpm exec expo start --dev-client --host lan "${EXTRA_EXPO_ARGS[@]}"
