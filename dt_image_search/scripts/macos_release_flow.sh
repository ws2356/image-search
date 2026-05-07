#!/usr/bin/env bash
set -euo pipefail

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
repo_root="$(cd "${this_dir}/../.." && pwd)"
parent_repo_root="$(dirname "$repo_root")"
parent_repo="ws2356/ausearch-release"

build_type=prod
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-type) build_type="$2"; shift 2;;
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

"$this_dir/build_pyinstaller.sh"

set -a; . "$repo_root/.env"; set +a
APPLE_APP_SPECIFIC_PASSWORD=$(security find-generic-password -l 'apple app specific password - ws2356' -w)
export APPLE_APP_SPECIFIC_PASSWORD

"$this_dir/create_distributable_dmg.sh" --app-path "$repo_root/pyinstaller-dist-${build_type}/AuSearch.app"

(cd "$parent_repo_root" && git push && "$this_dir/create_github_release.sh" \
    --repo "$parent_repo" --tag "$tag" \
    --title "Release $tag" --notes "Bug free code" \
    --dmg-path "$repo_root/pyinstaller-dist-${build_type}/AuSearch.dmg" --target main)

(cd "$repo_root/web" && \
    export AUSEARCH_MACOS_DOWNLOAD_URL="https://github.com/$parent_repo/releases/download/$tag/AuSearch.dmg" && \
    npm run build && \
    npm run sync)