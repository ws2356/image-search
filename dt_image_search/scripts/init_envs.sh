#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
repo_root="$(cd "${this_dir}/../.." && pwd)"

set -a; . "$repo_root/dt_image_search/.env-applecredential"; set +a

# Prefer a dedicated build keychain: reading the app-specific password from the
# login keychain would otherwise require unlocking (and prompting for) the
# login keychain password.  The custom keychain is unlocked non-interactively
# with its own password, stored in a local gitignored env file.
keychain="$HOME/Library/Keychains/cicd-ausearch.keychain-db"
if [ -f "$keychain" ]; then
    cred_file="$repo_root/dt_image_search/.env-build-keychain"
    if [ -f "$cred_file" ]; then
        set -a; . "$cred_file"; set +a
    fi
    if [ -z "${DTIS_BUILD_KEYCHAIN_PASSWORD:-}" ]; then
        echo "Error: $cred_file missing or DTIS_BUILD_KEYCHAIN_PASSWORD not set" >&2
        exit 1
    fi
    security unlock-keychain -p '' "$keychain"
    APPLE_APP_SPECIFIC_PASSWORD=$(security find-generic-password -w "$keychain" -l 'apple app specific password - ws2356' || true)
fi
if [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ] ; then
    echo "Failed to find APPLE_APP_SPECIFIC_PASSWORD"
    exit 1
fi
export APPLE_APP_SPECIFIC_PASSWORD
