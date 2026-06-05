#!/usr/bin/env bash
set -euo pipefail

# TODO: revert this. only for debugging
exit 0

# Submits a DMG to Apple for notarization, waits for the result, and exits
# non-zero if notarization is not accepted.  On failure the Apple log is
# fetched and printed so you can diagnose the issue.
#
# Required environment variables:
#   APPLE_ID                    Apple ID (email address)
#   APPLE_APP_SPECIFIC_PASSWORD App-specific password — generate at
#                               https://appleid.apple.com/account/manage
#   APPLE_TEAM_ID               10-character Apple Developer Team ID
#
# Usage:
#   APPLE_ID=you@example.com \
#   APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#   APPLE_TEAM_ID=ABCDE12345 \
#   notarize.sh --dmg-path ./dist/AuSearch-1.2.3.dmg
#   notarize.sh --pkg-path ./dist/AuSearch-1.2.3.pkg

ARTIFACT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg-path) ARTIFACT_PATH="$2"; shift 2 ;;
        --pkg-path) ARTIFACT_PATH="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$ARTIFACT_PATH" ]] && { echo "Error: --dmg-path or --pkg-path is required" >&2; exit 1; }
[[ -f "$ARTIFACT_PATH" ]] || { echo "Error: artifact not found: $ARTIFACT_PATH" >&2; exit 1; }

for var in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID; do
    [[ -n "${!var:-}" ]] || { echo "Error: \$$var is required" >&2; exit 1; }
done

echo "Submitting for notarization: $ARTIFACT_PATH"
echo "(This typically takes 1–5 minutes...)"
echo ""

OUTPUT=$(xcrun notarytool submit "$ARTIFACT_PATH" \
    --apple-id     "$APPLE_ID" \
    --password     "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id      "$APPLE_TEAM_ID" \
    --output-format json \
    --wait)

echo "$OUTPUT"

STATUS=$(echo "$OUTPUT" \
    | python3 -c "import sys, json; print(json.load(sys.stdin).get('status','unknown'))")
SUBMISSION_ID=$(echo "$OUTPUT" \
    | python3 -c "import sys, json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null \
    || echo "")

if [[ "$STATUS" != "Accepted" ]]; then
    echo "" >&2
    echo "ERROR: Notarization failed (status: $STATUS)" >&2
    if [[ -n "$SUBMISSION_ID" ]]; then
        echo "Fetching Apple notarization log for submission $SUBMISSION_ID..." >&2
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id  "$APPLE_TEAM_ID" >&2 || true
    fi
    exit 1
fi

echo ""
echo "Notarization accepted!  Run staple_dmg.sh to embed the ticket."
