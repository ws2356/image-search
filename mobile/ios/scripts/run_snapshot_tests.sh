#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AlbumTransporterApp.xcodeproj"
SCHEME_NAME="AlbumTransporterApp"
TEST_TARGET="AlbumTransporterAppSnapshotTests"
DERIVED_DATA_PATH="$ROOT_DIR/build/derived-data/snapshot-tests"
SNAPSHOT_CONFIG_PATH="$ROOT_DIR/build/snapshot-config.json"
SNAPSHOT_LANGUAGE="${SNAPSHOT_LANGUAGE:-en-US}"

MODE=test
TEST_ID="$TEST_TARGET"
TARGET_DEVICE=

while [ "$#" -gt 0 ]; do
  case "$1" in
    -t|--test-id)
      TEST_ID="$2"
      shift ; shift
      ;;
    -m|--mode)
      MODE="$2"
      shift ; shift
      ;;
    -d|--device)
      TARGET_DEVICE="$2"
      shift ; shift
      ;;
    *)
      echo "Usage: $0 [-t <test-class>] [-m test|record] [-d <device>]" >&2
      echo "  -t, --test-class  Run only a specific test class (e.g. InstantShareSnapshotTests)" >&2
      echo "  -m, --mode        Mode: test (default) or record" >&2
      echo "  -d, --device      Target device (e.g. iPhone|iPad)" >&2
      exit 1
      ;;
  esac
done

default_test_ids=("AlbumTransporterAppSnapshotTests/AlbumTransporterAppSnapshotTests" "AlbumTransporterAppSnapshotTests/InstantShareSnapshotTests")
if [ -n "$TEST_ID" ]; then
  is_valid_test_target=false
  for default_test_id in "${default_test_ids[@]}"; do
    if [ "$default_test_id" == "$TEST_ID" ]; then
      is_valid_test_target=true
      break
    elif [[ "$TEST_ID" == "$default_test_id"/* ]]; then
      is_valid_test_target=true
      break
    elif [[ "$default_test_id" == "$TEST_ID"/* ]]; then
      is_valid_test_target=true
      break
    fi
  done
  if [[ "$is_valid_test_target" == false ]]; then
    echo "Invalid test target: $TEST_ID" >&2
    exit 1
  fi
fi

target_device_list=()
if [ "$TARGET_DEVICE" == "iPhone" ]; then
  target_device_list+=("iPhone 17 Pro Max")
elif [ "$TARGET_DEVICE" == "iPad" ]; then
  target_device_list+=("iPad Pro 13-inch")
elif [ -z "$TARGET_DEVICE" ]; then
  target_device_list+=("iPhone 17 Pro Max" "iPad Pro 13-inch")
else
  echo "Invalid device: $TARGET_DEVICE" >&2
  exit 1
fi

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
  echo "Usage: $0 [-t <test-class>] [-m test|record]" >&2
  echo "  -t, --test-class  Run only a specific test class (e.g. InstantShareSnapshotTests)" >&2
  echo "  -m, --mode        Mode: test (default) or record" >&2
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

  echo "==> Running $MODE snapshots for $simulator_name ($SNAPSHOT_LANGUAGE), tests: $TEST_ID"
  mkdir -p "$(dirname "$SNAPSHOT_CONFIG_PATH")"
  cat >"$SNAPSHOT_CONFIG_PATH" <<EOF
{"record": ${RECORD_LITERAL}, "language": "${SNAPSHOT_LANGUAGE}", "deviceAlias": "${alias_name}"}
EOF
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -destination "platform=iOS Simulator,name=$simulator_name" \
    -only-testing:"$TEST_ID" \
    -testLanguage "$language_code" \
    -testRegion "$region_code" \
    -skipMacroValidation
}

cleanup() {
  rm -f "$SNAPSHOT_CONFIG_PATH"
}

trap cleanup EXIT

for device in "${target_device_list[@]}"; do
  run_for_device "$device"
done
