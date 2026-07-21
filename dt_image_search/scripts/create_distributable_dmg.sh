#!/usr/bin/env bash
set -euo pipefail

# End-to-end macOS notarized distribution pipeline:
#   1. Codesign .app     (Hardened Runtime, inside-out)
#   2. Package DMG       (.app + /Applications symlink, signed DMG)
#   3. Notarize DMG      (xcrun notarytool, waits for Accepted status)
#   4. Staple DMG        (embeds ticket for offline verification)
#
# Version and Info.plist keys are set in dt_image_search/resources/AppInfo.plist
# and injected at build time by the PyInstaller spec — update that file and
# rebuild before running this script.
#
# Usage:
#   distribute_macos.sh \
#       --app-path  ./pyinstaller-dist-prod/AuSearch.app \
#       [--identity "Developer ID Application: NAME (TEAMID)"] \
#       [--skip-notarize]
#
# Required env vars (for notarization):
#   APPLE_ID                    Apple ID (email)
#   APPLE_APP_SPECIFIC_PASSWORD App-specific password from appleid.apple.com
#   APPLE_TEAM_ID               10-character team ID
#
# The signing identity may also be supplied via $DEVELOPER_ID_IDENTITY.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR/../.."

APP_PATH=""
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
SKIP_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)      APP_PATH="$2";   shift 2 ;;
        --identity)      IDENTITY="$2";   shift 2 ;;
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH" ]] && { echo "Error: --app-path is required"  >&2; exit 1; }
if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$(pwd)/$APP_PATH"
fi

APP_NAME="$(basename "$APP_PATH" .app)"
OUTPUT_DMG="$(dirname "$APP_PATH")/$(basename "$APP_PATH" .app).dmg"


echo "╔══════════════════════════════════════════╗"
echo "║  macOS Distribution Pipeline             ║"
echo "╠══════════════════════════════════════════╣"
echo "  App:    $APP_PATH"
echo "  Output: $OUTPUT_DMG"

VOLNAME="$(basename "$APP_PATH" .app)"
DMG_ARGS=(--app-path "$APP_PATH" --volume-name "$VOLNAME")
[[ -n "$IDENTITY" ]] && DMG_ARGS+=(--identity "$IDENTITY")
"$SCRIPT_DIR/package_dmg.sh" "${DMG_ARGS[@]}"
echo ""

if [[ "$SKIP_NOTARIZE" == "true" ]]; then
    echo "--skip-notarize set — skipping notarization and stapling."
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Done (unsigned)  $OUTPUT_DMG"
    echo "╚══════════════════════════════════════════╝"
    exit 0
fi