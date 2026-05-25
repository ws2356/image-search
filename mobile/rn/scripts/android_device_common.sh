#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"
ANDROID_APP_ID="com.ausearch.aubackup"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

list_online_device_serials() {
  adb devices | awk 'NR > 1 && $2 == "device" { print $1 }'
}

resolve_device_serial() {
  local requested_serial="${1:-${ANDROID_SERIAL:-}}"
  if [[ -n "$requested_serial" ]]; then
    echo "$requested_serial"
    return 0
  fi

  mapfile -t serials < <(list_online_device_serials)
  if [[ "${#serials[@]}" -eq 0 ]]; then
    echo "No online Android devices found. Connect a device and ensure adb authorization is completed." >&2
    exit 1
  fi

  if [[ "${#serials[@]}" -gt 1 ]]; then
    echo "Multiple Android devices detected. Re-run with --serial <device-serial>." >&2
    printf 'Detected serials:\n%s\n' "${serials[@]}" >&2
    exit 1
  fi

  echo "${serials[0]}"
}

assert_device_online() {
  local serial="$1"
  if ! adb devices | awk 'NR > 1 && $1 == "'"$serial"'" && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }'; then
    echo "Android device '$serial' is not online. Check cable, authorization, and adb status." >&2
    exit 1
  fi
}

setup_adb_reverse() {
  local serial="$1"
  adb -s "$serial" reverse tcp:8081 tcp:8081 >/dev/null
}

launch_installed_app() {
  local serial="$1"
  adb -s "$serial" shell monkey -p "$ANDROID_APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || {
    echo "Failed to launch app package '$ANDROID_APP_ID' on device '$serial'." >&2
    exit 1
  }
}
