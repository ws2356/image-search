#!/usr/bin/env bash
set -euo pipefail

distpath=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --distpath) distpath="$2"; shift 2;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
    esac
done

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi

this_dir="$(dirname "$this_file")"
project_root="${this_dir}/../.."

"$this_dir/compile_pyside6_ui.sh"

if [ -z "$distpath" ]; then
    distpath="$project_root/pyinstaller-dist"
fi
pyinstaller "$project_root/dt_image_search/DTImageSearch.spec"  --noconfirm --clean --distpath "$distpath"

bash "$this_dir/prune_macos_bundle.sh" --app-path "${distpath}/AuSearch.app"
echo "PyInstaller build completed. Output located at: $distpath"
