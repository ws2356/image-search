#!/usr/bin/env bash
set -euo pipefail

# Staples the Apple notarization ticket to a PKG so end-users can verify
# the notarization without a network connection. Run after notarize.sh.
#
# Usage:
#   staple_pkg.sh --pkg-path ./dist/AuSearch-1.2.3.pkg

PKG_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkg-path) PKG_PATH="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$PKG_PATH" ]] && { echo "Error: --pkg-path is required" >&2; exit 1; }
[[ -f "$PKG_PATH" ]] || { echo "Error: PKG not found: $PKG_PATH" >&2; exit 1; }

echo "Stapling notarization ticket: $PKG_PATH"
xcrun stapler staple "$PKG_PATH"

echo "Validating staple..."
xcrun stapler validate "$PKG_PATH"

echo "Done.  $PKG_PATH is ready for distribution."
