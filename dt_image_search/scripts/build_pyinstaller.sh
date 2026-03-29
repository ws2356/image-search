#!/usr/bin/env bash
set -euo pipefail

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi

this_dir="$(dirname "$this_file")"
project_root="${this_dir}/../.."

"$this_dir/compile_pyside6_ui.sh"

pyinstaller "$project_root/dt_image_search/DTImageSearch.spec"  --noconfirm --clean