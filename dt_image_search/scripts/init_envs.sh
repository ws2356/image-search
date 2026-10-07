#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
repo_root="$(cd "${this_dir}/../.." && pwd)"

# Credential sources, in priority order:
#   1. The dedicated, passwordless build keychain (empty password is by design,
#      so it can always be unlocked non-interactively in CI/automation sessions).
#   2. The gitignored .env-applecredential file (legacy fallback; also holds the
#      non-secret identifiers below).
cred_file="$repo_root/dt_image_search/.env-applecredential"
if [ ! -f "$cred_file" ]; then
    echo "Error: credential file not found: $cred_file" >&2
    exit 1
fi
set -a; . "$cred_file"; set +a

keychain="$HOME/Library/Keychains/cicd-ausearch.keychain-db"
if [ -f "$keychain" ]; then
    security unlock-keychain -p '' "$keychain"
    found_pw=$(security find-generic-password -w "$keychain" -l 'apple app specific password - ws2356' 2>/dev/null || true)
    if [ -n "$found_pw" ]; then
        APPLE_APP_SPECIFIC_PASSWORD="$found_pw"
    fi
fi

# Reusable helper: find a generic-password item by its label in the dedicated
# build keychain (new secrets should be added there, then wired up like the
# app-specific password above).
find_keychain_item() {
    local label="$1"
    security find-generic-password -w "$keychain" -l "$label" 2>/dev/null
}

for var in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID DEVELOPER_ID_IDENTITY DEVELOPER_ID_INSTALLER; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set (keychain: $keychain or $cred_file)" >&2
        exit 1
    fi
done

export APPLE_APP_SPECIFIC_PASSWORD APPLE_ID APPLE_TEAM_ID
export DEVELOPER_ID_IDENTITY DEVELOPER_ID_INSTALLER

# Keychain that holds the signing identities (same dedicated, passwordless
# keychain as above).  Signing scripts pass it to codesign/pkgbuild explicitly
# because automation sessions (launchd daemons, SSH) do not inherit the user's
# keychain search list.
if [ -f "$keychain" ]; then
    export DEVELOPER_ID_KEYCHAIN="$keychain"
fi
