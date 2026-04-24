#!/usr/bin/env bash
set -euo pipefail

# Staples the Apple notarization ticket to a DMG so end-users can verify
# the notarization without a network connection.  Run after notarize.sh.
#
# Usage:
#   staple_dmg.sh --dmg-path ./dist/AuSearch-1.2.3.dmg

DMG_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg-path) DMG_PATH="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$DMG_PATH" ]] && { echo "Error: --dmg-path is required" >&2; exit 1; }
[[ -f "$DMG_PATH" ]] || { echo "Error: DMG not found: $DMG_PATH" >&2; exit 1; }

echo "Stapling notarization ticket: $DMG_PATH"
xcrun stapler staple "$DMG_PATH"

echo "Validating staple..."
xcrun stapler validate "$DMG_PATH"

echo "Done.  $DMG_PATH is ready for distribution."
