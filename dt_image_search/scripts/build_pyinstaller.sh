#!/usr/bin/env bash
# -- Build AuSearch.app (main) or InstantShare.app (instant-share)
# -- For snapget, build and embed Share Extension
set -euo pipefail

distpath=""
build_type="${DTIS_BUILD_TYPE:-prod}"
product="main"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-type) build_type="$2"; shift 2;;
        --distpath) distpath="$2"; shift 2;;
        --product) product="$2"; shift 2;;
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

if [[ -d "$distpath" ]]; then
    (cd "$distpath" && sudo rm -rf ./*.app)
fi

case "$product" in
    main)
        spec_file="dt_image_search/DTImageSearch_MainApp.spec"
        app_name="AuSearch"
        ;;
    snapget)
        spec_file="dt_image_search/DTImageSearch_InstantShare.spec"
        app_name="SnapGet"
        ;;
    *)
        echo "Unknown product: $product. Expected 'main' or 'snapget'."
        exit 1
        ;;
esac

if [[ "$build_type" != "prod" ]]; then
    app_name="${app_name}-${build_type}"
fi

(cd "$project_root" && pyinstaller "$spec_file" --noconfirm --clean --distpath "$distpath")

app_path="${distpath}/${app_name}.app"

if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ ! -d "$app_path" ]]; then
        echo "Expected app bundle not found: $app_path"
        exit 1
    fi

    main_bin="${app_path}/Contents/MacOS/${app_name}"
    if [[ ! -f "$main_bin" ]]; then
        echo "Expected binary not found: $main_bin"
        exit 1
    fi

    if [[ "$product" == "snapget" ]]; then
        # Build and embed Share Extension
        echo "==> Building Share Extension..."
        bash "$this_dir/build_share_extension.sh" --app-path "$app_path"
        share_appex="${app_path}/Contents/PlugIns/ShareExtension.appex"
        if [[ ! -d "$share_appex" ]]; then
            echo "Expected ShareExtension.appex not found at $share_appex"
            exit 1
        fi
        echo "  ShareExtension.appex bundled at $share_appex"
    fi

    bash "$this_dir/prune_macos_bundle.sh" --app-path "$app_path"
fi

echo "PyInstaller build completed for ${product}. Output located at: ${distpath}/${app_name}.app"
