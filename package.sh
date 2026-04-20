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

spec_path="dt_image_search/DTImageSearch.spec"
if [[ ! -f "$spec_path" ]]; then
  spec_path="DTImageSearch.spec"
fi

export DTIS_BUILD_TYPE="$build_type"
rm -rf ./build ./dist && pyinstaller "$spec_path"
