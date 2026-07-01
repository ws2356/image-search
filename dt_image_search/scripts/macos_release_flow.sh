#!/usr/bin/env bash
set -euo pipefail

# End-to-end macOS release flow.
#
# Builds the .app with PyInstaller, signs it, packages a notarized PKG
# installer, creates a GitHub release, and uploads the PKG asset.
#
# Supports two products:
#   --product main-app       AuSearch (image search, no ShareExtension)
#   --product instant-share  InstantShare (standalone sharing app with ShareExtension)
#
# The PKG installer includes a LaunchAgent that auto-starts the instant
# share daemon at login for instant-share builds.  The following permissions
# are requested from the user at first launch via entitlements and Info.plist
# usage descriptions:
#   - Local network access (mDNS advertising + HTTP server)
#   - Internet access (telemetry)
#   - Apple Events (Finder integration)

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
repo_root="$(cd "${this_dir}/../.." && pwd)"
parent_repo_root="$(dirname "$repo_root")"
parent_repo="ws2356/ausearch-release"

build_type=prod
product="main-app"
skip_release=false
skip_build=false
skip_pkg=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-type) build_type="$2"; shift 2;;
        --product) product="$2"; shift 2;;
        --skip-release) skip_release=true; shift;;
        --skip-build) skip_build=true; shift;;
        --skip-pkg) skip_pkg=true; shift;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
    esac
done

case "$product" in
    main-app)
        app_bundle_name="AuSearch"
        pkg_identifier="vip.wansong.dtimagesearch"
        ;;
    instant-share)
        app_bundle_name="InstantShare"
        pkg_identifier="vip.wansong.dtimagesearch.instantshare"
        ;;
    *)
        echo "Unknown product: $product. Expected 'main-app' or 'instant-share'."
        exit 1
        ;;
esac

if [[ "$build_type" != "prod" ]]; then
    app_bundle_name="${app_bundle_name}-${build_type}"
fi

# Check parent repository exists
parent_repo_url="$(cd "$parent_repo_root" && git config --get remote.origin.url)"
if [[ "$parent_repo_url" != "https://github.com/$parent_repo.git" ]]; then
    echo "Error: Parent repository URL does not match expected '$parent_repo'. Found: '$parent_repo_url'"
    exit 1
fi

# Get tag from CFBundleVersion in dt_image_search/resources/AppInfo.plist
app_info_plist="$repo_root/dt_image_search/resources/AppInfo.plist"
if [[ ! -f "$app_info_plist" ]]; then
    echo "Error: AppInfo.plist not found at expected path: $app_info_plist"
    exit 1
fi
tag="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app_info_plist")"
if [[ -z "$tag" ]]; then
    echo "Error: CFBundleVersion not found or empty in AppInfo.plist"
    exit 1
fi

echo "Using tag: $tag"
echo "Product: $product"
echo "App bundle name: $app_bundle_name"

cd "$repo_root"

if [ "$skip_build" = false ] ;  then
    # -- Step 1: Export variables like DEVELOPER_ID_IDENTITY, etc from .env
    . "$this_dir/init_envs.sh"

    # -- Step 2: Build the .app
    "$this_dir/build_pyinstaller.sh" \
        --build-type "$build_type" \
        --product "$product"

    if [ "$skip_pkg" = false ] ;  then
        distpath="$repo_root/pyinstaller-dist-${build_type}"

        # -- Step 3: Build and notarize the PKG distribution
        "$this_dir/create_distributable_pkg.sh" \
            --app-path "${distpath}/${app_bundle_name}.app"

        # -- Step 4: Forget and remove old bundle (helpful for local testing)
        sudo pkgutil --forget "$pkg_identifier" || true
        # (cd "$distpath" && sudo rm -rf "./${app_bundle_name}.app")
    fi
fi

if [ "$skip_release" = false ]; then
    # -- Step 5: Push to Github Release
    pkg_file="${app_bundle_name}.pkg"
    (cd "$parent_repo_root" && git push && "$this_dir/create_github_release.sh" \
        --repo "$parent_repo" --tag "$tag" \
        --title "Release $tag ($product)" --notes "Bug free code" \
        --pkg-path "$repo_root/pyinstaller-dist-${build_type}/$pkg_file" --target main)

    # -- Step 6: Release to Official Side (only for main-app)
    if [[ "$product" == "main-app" ]]; then
        (cd "$repo_root/web" && \
            export AUSEARCH_MACOS_DOWNLOAD_URL="https://github.com/$parent_repo/releases/download/$tag/${app_bundle_name}.pkg" && \
            npm run build && \
            npm run sync)
    fi
fi
