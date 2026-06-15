#!/usr/bin/env bash
# -- Build AuSearch.app and InstantShareAgent
# -- Set up a sub bundle for InstantShareAgent
# -- Build InstantShare extension
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

if [[ -d "$distpath" ]]; then
    (cd "$distpath" && sudo rm -rf ./*.app)
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

    # Verify both binaries exist inside the app bundle
    main_bin="${app_path}/Contents/MacOS/${app_name}"
    daemon_bin="${app_path}/Contents/MacOS/InstantShareAgent"
    if [[ ! -f "$main_bin" ]]; then
        echo "Expected desktop binary not found: $main_bin"
        exit 1
    fi
    if [[ ! -f "$daemon_bin" ]]; then
        echo "Expected daemon binary not found: $daemon_bin"
        exit 1
    fi

    # Create a sub bundle for the agent inside the main bundle's Helpers directory
    agent_bundle_path="${app_path}/Contents/Helpers/InstantShareAgent.app"
    mkdir -p "${agent_bundle_path}/Contents/MacOS"
    mv "$daemon_bin" "${agent_bundle_path}/Contents/MacOS/InstantShareAgent"
    # soft link all Contents/* to the agent bundle so it can find the resources and plist
    (cd "$agent_bundle_path/Contents" && ln -s "../../../Resources" . && ln -s "../../../Frameworks" .)
    # copy Info.plist
    cp "${project_root}/dt_image_search/resources/AppInfoInstantShare.plist" "${agent_bundle_path}/Contents/Info.plist"


    # Build and embed Share Extension
    echo "==> Building Share Extension..."
    bash "$this_dir/build_share_extension.sh" --app-path "$app_path"
    share_appex="${app_path}/Contents/PlugIns/ShareExtension.appex"
    if [[ ! -d "$share_appex" ]]; then
        echo "Expected ShareExtension.appex not found at $share_appex"
        exit 1
    fi
    echo "  ShareExtension.appex bundled at $share_appex"

    bash "$this_dir/prune_macos_bundle.sh" --app-path "$app_path"
fi

echo "PyInstaller build completed. Output located at: $distpath"
