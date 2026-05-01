#!/usr/bin/env bash
set -euo pipefail

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
repo_root="${this_dir}/../.."
parent_repo_root="$(dirname "$repo_root")"
parent_repo="ws2356/ausearch-release"

# Check parent repository exists
parent_repo_url="$(cd "$parent_repo_root" && git config --get remote.origin.url)"
if [[ "$parent_repo_url" != "https://github.com/$parent_repo.git" ]]; then
    echo "Error: Parent repository URL does not match expected '$parent_repo'. Found: '$parent_repo_url'"
    exit 1
fi

tag=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --tag) tag="$2"; shift 2;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
    esac
done

if [ -z "$tag" ]; then
    echo "Error: --tag parameter is required."
    exit 1
fi

"$this_dir/build_pyinstaller.sh"

"$this_dir/distribute_macos.sh" --app-path "$repo_root/pyinstaller-dist/AuSearch.app"

(cd "$parent_repo_root" && "$this_dir/create_github_release.sh" \
    --repo "$parent_repo" --tag "$tag" \
    --title "Release $tag" --notes "Bug free code" \
    --dmg-path "$repo_root/pyinstaller-dist/AuSearch.dmg" --target main)

(cd "$repo_root/web" && \
    export AUSEARCH_MACOS_DOWNLOAD_URL="https://github.com/$parent_repo/releases/download/$tag/AuSearch.dmg" && \
    npm run build && \
    npm run sync)