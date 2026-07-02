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
skip_notarize=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-type) build_type="$2"; shift 2;;
        --product) product="$2"; shift 2;;
        --skip-release) skip_release=true; shift;;
        --skip-build) skip_build=true; shift;;
        --skip-pkg) skip_pkg=true; shift;;
        --skip-notarize) skip_notarize=true; shift;;
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

# Get tag from the product-specific plist
case "$product" in
    main-app)
        app_info_plist="$repo_root/dt_image_search/resources/AppInfo.plist"
        ;;
    instant-share)
        app_info_plist="$repo_root/dt_image_search/resources/AppInfoInstantShare.plist"
        ;;
esac
if [[ ! -f "$app_info_plist" ]]; then
    echo "Error: plist not found at expected path: $app_info_plist"
    exit 1
fi
tag="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app_info_plist")-$product"
if [[ -z "$tag" ]]; then
    echo "Error: CFBundleVersion not found or empty in $app_info_plist"
    exit 1
fi

echo "Using tag: $tag"
echo "Product: $product"
echo "App bundle name: $app_bundle_name"

cd "$repo_root"

package_file=
distpath="$repo_root/pyinstaller-dist-${build_type}"
app_path="${distpath}/${app_bundle_name}.app"

if [ "$skip_build" == false ] ;  then
    echo "──── Step 1: Export variables like DEVELOPER_ID_IDENTITY, etc from .env"
    . "$this_dir/init_envs.sh"

    echo "──── Step 2: Build the .app"
    "$this_dir/build_pyinstaller.sh" \
        --build-type "$build_type" \
        --product "$product"
    
    if [ -z "$DEVELOPER_ID_IDENTITY" ]; then
        echo "Warning: DEVELOPER_ID_IDENTITY is not set."
        exit 1
    fi

    echo "──── Step 3: Codesign the .app"
    "$this_dir/codesign_app.sh" \
        --app-path "$app_path" \
        --entitlements "$this_dir/../resources/${app_bundle_name}.entitlements" \
        --identity "$DEVELOPER_ID_IDENTITY"

    if [ "$skip_pkg" == false ] ;  then
        if [ "$product" == "instant-share" ]; then
            echo "──── Step 4: Build the PKG distribution"
            "$this_dir/package_pkg.sh" \
                --app-path "$app_path" \
                --identity "$DEVELOPER_ID_INSTALLER"
            package_file="${distpath}/${app_bundle_name}.pkg"
        elif [ "$product" == "main-app" ]; then
            echo "──── Step 4: Build the DMG distribution"
            "$this_dir/package_dmg.sh" \
                --app-path "$app_path" \
                --volume-name "$app_bundle_name" \
                --identity "$DEVELOPER_ID_IDENTITY"
            package_file="${distpath}/${app_bundle_name}.dmg"
        else
            echo "Unknown product: $product. Expected 'main-app' or 'instant-share'."
            exit 1
        fi

        if [ "$skip_notarize" == false ] ; then
            echo "──── Step 5: Notarize ────"
            "$this_dir/notarize.sh" --asset-path "$package_file"
            echo ""

            echo "──── Step 6: Staple ────"
            "$this_dir/staple.sh" --asset-path "$package_file"
            echo ""
        fi

        echo "──── Step 7: Forget and remove old bundle (helpful for local testing)"
        sudo pkgutil --forget "$pkg_identifier" || true

        echo "──── Step 8: Remove the app bundle if it exists to ensure a clean install for testing"
        sudo rm -rf "$app_path"
    fi
else
    if [ "$product" == "instant-share" ]; then
        package_file="${distpath}/${app_bundle_name}.pkg"
    elif [ "$product" == "main-app" ]; then
        package_file="${distpath}/${app_bundle_name}.dmg"
    fi
fi

if [ "$skip_release" = false ]; then
    # -- Step 5: Push to Github Release
    if [ -z "$package_file" ] || ! [ -f "$package_file" ]; then
        echo "Error: Package file not found. Ensure build and packaging steps completed successfully."
        exit 1
    fi

    echo "──── Step 8: Push to Github Release"
    "$this_dir/create_github_release.sh" \
            --product "$product" --tag "$tag" \
            --title "Release $tag ($product)" --notes "Bug free code" \
            --asset-path "$package_file" --target main

    echo "──── Step 9: Release to Official Side (only for main-app)"
    release_json="$repo_root/releases.json"
    download_main="$(python3 -c "import json; print(json.load(open('$release_json'))['main-app']['download_url'])")"
    download_is="$(python3 -c "import json; print(json.load(open('$release_json'))['instant-share']['download_url'])")"
    (cd "$repo_root/web" && \
        export AUSEARCH_MACOS_DOWNLOAD_URL="$download_main" && \
        export INSTANTSHARE_DOWNLOAD_URL="$download_is" && \
        npm run build && \
        npm run sync)
fi

echo "──── Done!"