#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Tests/AlbumTransporterAppSnapshotTests/__Snapshots__"
OUTPUT_DIR="$ROOT_DIR/build/marketing-screenshots"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' is required to export screenshots without alpha channels." >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Snapshot source directory not found: $SOURCE_DIR" >&2
  echo "Record snapshots first with: $ROOT_DIR/scripts/run_snapshot_tests.sh record" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

while IFS= read -r source_path; do
  filename="$(basename "$source_path")"
  magick "$source_path" -background white -alpha remove -alpha off "$OUTPUT_DIR/$filename"
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.png' | sort)

echo "Exported marketing screenshots to $OUTPUT_DIR"
