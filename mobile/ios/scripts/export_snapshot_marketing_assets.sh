#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Tests/AlbumTransporterAppSnapshotTests/__Snapshots__"
OUTPUT_DIR="$ROOT_DIR/build/marketing-screenshots"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Snapshot source directory not found: $SOURCE_DIR" >&2
  echo "Record snapshots first with: $ROOT_DIR/scripts/run_snapshot_tests.sh record" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.png' -exec cp '{}' "$OUTPUT_DIR/" ';'

echo "Exported marketing screenshots to $OUTPUT_DIR"
