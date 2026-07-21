#!/usr/bin/env bash
set -euo pipefail

# Staples the Apple notarization ticket to a PKG so end-users can verify
# the notarization without a network connection. Run after notarize.sh.
#
# Usage:
#   staple_pkg.sh --pkg-path ./dist/AuSearch-1.2.3.pkg

ASSET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --asset-path) ASSET_PATH="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$ASSET_PATH" ]] && { echo "Error: --asset-path is required" >&2; exit 1; }
[[ -f "$ASSET_PATH" ]] || { echo "Error: Asset not found: $ASSET_PATH" >&2; exit 1; }

echo "Stapling notarization ticket: $ASSET_PATH"
xcrun stapler staple "$ASSET_PATH"

echo "Validating staple..."
xcrun stapler validate "$ASSET_PATH"

echo "Done.  $ASSET_PATH is ready for distribution."
