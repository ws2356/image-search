#!/usr/bin/env bash
set -euo pipefail

distpath=""
build_type="${DTIS_BUILD_TYPE:-prod}"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-type) build_type="$2"; shift 2;;
        --distpath) distpath="$2"; shift 2;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
    esac
done

if [ -n "$distpath" ] && [[ "$distpath" != /* ]]; then
    distpath="$(pwd)/$distpath"
fi

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi

this_dir="$(dirname "$this_file")"
project_root="${this_dir}/../.."

if [ -n "$build_type" ]; then
    if [[ "$build_type" != "prod" && "$build_type" != "dev" ]]; then
        echo "Unsupported build type: $build_type. Expected 'prod' or 'dev'."
        exit 1
    fi
    export DTIS_BUILD_TYPE="$build_type"
fi

revision="$(git -C "$project_root" rev-parse HEAD)"
export DTIS_REVISION="$revision"

"$this_dir/compile_pyside6_ui.sh"

if [ -z "$distpath" ]; then
    distpath="$project_root/pyinstaller-dist-${build_type}"
fi

(cd "$project_root" && pyinstaller "dt_image_search/DTImageSearch.spec"  --noconfirm --clean --distpath "$distpath")

app_name="AuSearch"
if [[ "$build_type" != "prod" ]]; then
    app_name="AuSearch-${build_type}"
fi
app_path="${distpath}/${app_name}.app"

if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ ! -d "$app_path" ]]; then
        echo "Expected app bundle not found: $app_path"
        exit 1
    fi
    bash "$this_dir/prune_macos_bundle.sh" --app-path "$app_path"
fi

echo "PyInstaller build completed. Output located at: $distpath"
