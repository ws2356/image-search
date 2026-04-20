#!/usr/bin/env bash
set -euo pipefail

build_type="${DTIS_BUILD_TYPE:-prod}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-type)
      build_type="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ "$build_type" != "prod" && "$build_type" != "dev" ]]; then
  echo "Invalid build type: $build_type (expected: prod|dev)"
  exit 1
fi

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi

this_dir="$(dirname "$this_file")"
project_root="${this_dir}/../.."

export DTIS_BUILD_TYPE="$build_type"

"$this_dir/compile_pyside6_ui.sh"

pyinstaller "$project_root/dt_image_search/DTImageSearch.spec"  --noconfirm --clean --distpath "$project_root/pyinstaller-dist-$build_type"