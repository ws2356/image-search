#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
repo_root="$(cd "${this_dir}/../.." && pwd)"

set -a; . "$repo_root/.env.apple-auth"; set +a

APPLE_APP_SPECIFIC_PASSWORD=$(security find-generic-password -l 'apple app specific password - ws2356' -w)
if [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ] ; then
    echo "Failed to find APPLE_APP_SPECIFIC_PASSWORD"
    exit 1
fi
export APPLE_APP_SPECIFIC_PASSWORD