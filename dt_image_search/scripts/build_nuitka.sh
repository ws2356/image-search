#!/bin/bash
set -eu

script_path="$0"
if [[ "$script_path" != /* ]]; then
  script_path="$(pwd)/$script_path"
fi
script_dir="$(dirname "$script_path")"
cd "$script_dir/../.."

dev_args=()
for arg in "$@"; do
  if [[ "$arg" == "--dev" ]]; then
    dev_args+=("--no-lto" "---debug")
  fi
done


python -m nuitka \
  --standalone \
  --enable-plugin=pyside6 \
  --windows-icon-from-ico=dt_image_search/resources/icon.ico \
  --windows-company-name="Song Wan" \
  --windows-product-name="DTImageSearch" \
  --windows-file-version="1.0.0" \
  --output-dir=build \
  --output-filename=DTImageSearch \
  --include-package=dt_image_search \
  --windows-console-mode=force \
  --enable-caching \
  --jobs=8 \
  --include-package-data=open_clip \
  "${dev_args[@]}" \
  dt_image_search/__main__.py
