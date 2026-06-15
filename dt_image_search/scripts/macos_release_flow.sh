#!/usr/bin/env bash
set -euo pipefail

# End-to-end macOS release flow.
#
# Builds the .app with PyInstaller, signs it, packages a notarized PKG
# installer, creates a GitHub release, and uploads the PKG asset.
#
# The PKG installer includes a LaunchAgent that auto-starts the instant
# share daemon at login.  The following permissions are requested from
# the user at first launch via entitlements and Info.plist usage descriptions:
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
skip_release=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-type) build_type="$2"; shift 2;;
        --skip-release) skip_release=true; shift;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
    esac
done

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

cd "$repo_root"

# -- Step 1: Export variables like DEVELOPER_ID_IDENTITY, etc from .env
set -a; . "$repo_root/.env"; set +a

APPLE_APP_SPECIFIC_PASSWORD=$(security find-generic-password -l 'apple app specific password - ws2356' -w)
if [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ] ; then
    echo "Failed to find APPLE_APP_SPECIFIC_PASSWORD"
    exit 1
fi
export APPLE_APP_SPECIFIC_PASSWORD

# -- Step 2: Build AuSearch.app, InstantShareAgent.app (sub bundle), InstantShare Extension
"$this_dir/build_pyinstaller.sh"

# -- Step 3: Build and notarize the PKG distribution
"$this_dir/create_distributable_pkg.sh" \
    --app-path "$repo_root/pyinstaller-dist-${build_type}/AuSearch.app"

# -- Step 4: Forget and remove old bundle (helpful for local testing)
sudo pkgutil --forget 'vip.wansong.dtimagesearch' || true
(cd "$repo_root/pyinstaller-dist-${build_type}" && rm -rf ./AuSearch.app)

if [[ "$skip_release" == true ]]; then
    echo "Skipping GitHub release creation and asset upload as --skip-release flag is set."
    exit 0
fi

# -- Step 5: Push to Github Release
(cd "$parent_repo_root" && git push && "$this_dir/create_github_release.sh" \
    --repo "$parent_repo" --tag "$tag" \
    --title "Release $tag" --notes "Bug free code" \
    --pkg-path "$repo_root/pyinstaller-dist-${build_type}/AuSearch.pkg" --target main)

# -- Step 6: Release to Official Side
(cd "$repo_root/web" && \
    export AUSEARCH_MACOS_DOWNLOAD_URL="https://github.com/$parent_repo/releases/download/$tag/AuSearch.pkg" && \
    npm run build && \
    npm run sync)
