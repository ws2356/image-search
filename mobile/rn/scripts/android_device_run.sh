#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"

SERIAL=""
SKIP_BUILD=false
NO_METRO=false
EXPO_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      SERIAL="${2:-}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --no-metro)
      NO_METRO=true
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash scripts/android_device_run.sh [--serial <device-serial>] [--skip-build] [--no-metro] [-- <extra expo args...>]

Build/install app on a physical Android device, launch it, and start Metro for dev-client.

Options:
  --serial <device-serial>  Target adb serial; required when multiple devices are connected.
  --skip-build              Skip Gradle installDebug step.
  --no-metro                Do not start Metro after launching app.
  -- <args>                 Extra args passed to `expo start --dev-client --host lan`.
EOF
      exit 0
      ;;
    --)
      shift
      if [[ $# -eq 0 ]]; then
        break
      fi
      case "${1:-}" in
        --serial|--skip-build|--no-metro|--help|-h)
          ;;
        *)
          EXPO_ARGS=("$@")
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

TARGET_SERIAL="$(resolve_device_serial "$SERIAL")"
assert_device_online "$TARGET_SERIAL"

if [[ "$SKIP_BUILD" == false ]]; then
  bash "$SCRIPT_DIR/android_device_build.sh" --serial "$TARGET_SERIAL"
fi

echo "Configuring adb reverse for Metro (8081)..."
setup_adb_reverse "$TARGET_SERIAL"

echo "Launching app on device..."
launch_installed_app "$TARGET_SERIAL"

if [[ "$NO_METRO" == true ]]; then
  echo "App launched without starting Metro."
  exit 0
fi

cd "$PROJECT_ROOT"
exec pnpm exec expo start --dev-client --host lan "${EXPO_ARGS[@]}"
