#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AlbumTransporterApp.xcodeproj"
SCHEME_NAME="AlbumTransporterApp"
TEST_TARGET="AlbumTransporterAppSnapshotTests"
DERIVED_DATA_PATH="$ROOT_DIR/build/derived-data/snapshot-tests"
SNAPSHOT_CONFIG_PATH="$ROOT_DIR/build/snapshot-config.json"
SNAPSHOT_LANGUAGE="${SNAPSHOT_LANGUAGE:-en-US}"
MODE="${1:-test}"

if [[ "$MODE" == "record" ]]; then
  RECORD_SNAPSHOTS=1
  RECORD_LITERAL=true
elif [[ "$MODE" == "test" ]]; then
  RECORD_SNAPSHOTS="${RECORD_SNAPSHOTS:-0}"
  if [[ "$RECORD_SNAPSHOTS" == "1" ]]; then
    RECORD_LITERAL=true
  else
    RECORD_LITERAL=false
  fi
else
  echo "Usage: $0 [test|record]" >&2
  exit 1
fi

language_code="${SNAPSHOT_LANGUAGE%%-*}"
region_code="${SNAPSHOT_LANGUAGE#*-}"
if [[ "$region_code" == "$SNAPSHOT_LANGUAGE" ]]; then
  region_code="US"
fi

slugify() {
  printf '%s' "$1" | tr ' ' '-' | tr -cd '[:alnum:]-'
}

resolve_simulator_name() {
  local alias_name="$1"
  local devices
  devices="$(xcrun simctl list devices available)"

  case "$alias_name" in
    "iPhone 17 Pro Max")
      printf '%s\n' "$alias_name"
      ;;
    "iPad Pro 13-inch")
      printf '%s\n' "$devices" \
        | awk '/iPad Pro 13-inch/ { line=$0; sub(/^[[:space:]]*/, "", line); sub(/ \([0-9A-F-]+\) \(.*$/, "", line); print line; exit }' \
        | head -n 1
      ;;
    *)
      return 1
      ;;
  esac
}

run_for_device() {
  local alias_name="$1"
  local simulator_name
  simulator_name="$(resolve_simulator_name "$alias_name")"
  if [[ -z "$simulator_name" ]]; then
    echo "Could not resolve an available simulator for '$alias_name'." >&2
    exit 1
  fi

  echo "==> Running $MODE snapshots for $simulator_name ($SNAPSHOT_LANGUAGE)"
  mkdir -p "$(dirname "$SNAPSHOT_CONFIG_PATH")"
  cat >"$SNAPSHOT_CONFIG_PATH" <<EOF
{"record": ${RECORD_LITERAL}, "language": "${SNAPSHOT_LANGUAGE}", "deviceAlias": "${alias_name}"}
EOF
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -destination "platform=iOS Simulator,name=$simulator_name" \
    -only-testing:"$TEST_TARGET" \
    -derivedDataPath "$DERIVED_DATA_PATH/$(slugify "$alias_name")" \
    -testLanguage "$language_code" \
    -testRegion "$region_code"
}

cleanup() {
  rm -f "$SNAPSHOT_CONFIG_PATH"
}

trap cleanup EXIT

run_for_device "iPhone 17 Pro Max"
run_for_device "iPad Pro 13-inch"
