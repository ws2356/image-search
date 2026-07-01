#!/usr/bin/env bash
set -euo pipefail

# End-to-end macOS notarized distribution pipeline (PKG variant):
#   1. Codesign .app     (Hardened Runtime, inside-out)
#   2. Package PKG       (distribution package with LaunchAgent postinstall)
#   3. Notarize PKG      (xcrun notarytool, waits for Accepted status)
#   4. Staple PKG        (embeds ticket for offline verification)
#
# Version and Info.plist keys are set in dt_image_search/resources/AppInfo.plist
# and injected at build time by the PyInstaller spec — update that file and
# rebuild before running this script.
#
# Usage:
#   create_distributable_pkg.sh \
#       --app-path  ./pyinstaller-dist-prod/AuSearch.app \
#       [--app-identity "Developer ID Application: NAME (TEAMID)"] \
#       [--pkg-identity "Developer ID Installer: NAME (TEAMID)"] \
#       [--skip-notarize]
#
# Environment variables:
#   DEVELOPER_ID_IDENTITY    (fallback for --app-identity)
#   DEVELOPER_ID_INSTALLER   (fallback for --pkg-identity)
#   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID  (notarization)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

APP_PATH=""
APP_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
PKG_IDENTITY="${DEVELOPER_ID_INSTALLER:-}"
SKIP_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)      APP_PATH="$2";      shift 2 ;;
        --app-identity)  APP_IDENTITY="$2";  shift 2 ;;
        --pkg-identity)  PKG_IDENTITY="$2";  shift 2 ;;
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH"   ]] && { echo "Error: --app-path is required"  >&2; exit 1; }
if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$(pwd)/$APP_PATH"
fi
APP_NAME="$(basename "$APP_PATH" .app)"
OUTPUT_PKG="$(dirname "$APP_PATH")/$(basename "$APP_PATH" .app).pkg"

echo "╔══════════════════════════════════════════╗"
echo "║  macOS Distribution Pipeline (PKG)       ║"
echo "╠══════════════════════════════════════════╣"
echo "  App:    $APP_PATH"
echo "  Output: $OUTPUT_PKG"
[[ -n "$APP_IDENTITY" ]] && echo "  App identity:   $APP_IDENTITY"
[[ -n "$PKG_IDENTITY" ]] && echo "  PKG identity:   $PKG_IDENTITY"
echo ""

# Check for ShareExtension.appex (present in instant-share builds, absent in main-app)
SHARE_EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/ShareExtension.appex"
if [[ -d "$SHARE_EXTENSION_PATH" ]]; then
    echo "  ShareExtension.appex found — will be included in PKG."
else
    echo "  Note: No ShareExtension.appex — this is expected for main-app builds."
fi

# ── Step 1 ────────────────────────────────────────────────────────────────────
echo "──── Step 1: Codesign ────"
SIGN_ARGS=(--app-path "$APP_PATH" --entitlements "$SCRIPT_DIR/../resources/${APP_NAME}.entitlements")
[[ -n "$APP_IDENTITY" ]] && SIGN_ARGS+=(--identity "$APP_IDENTITY")
"$SCRIPT_DIR/codesign_app.sh" "${SIGN_ARGS[@]}"
echo ""

# ── Step 2 ────────────────────────────────────────────────────────────────────
echo "──── Step 2: Package PKG ────"
PKG_ARGS=(--app-path "$APP_PATH" --output "$OUTPUT_PKG")
[[ -n "$PKG_IDENTITY" ]] && PKG_ARGS+=(--identity "$PKG_IDENTITY")
"$SCRIPT_DIR/build_pkg.sh" "${PKG_ARGS[@]}"
echo ""

if [[ "$SKIP_NOTARIZE" == "true" ]]; then
    echo "--skip-notarize set — skipping notarization and stapling."
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Done (unsigned)  $OUTPUT_PKG"
    echo "╚══════════════════════════════════════════╝"
    exit 0
fi

# ── Step 3 ────────────────────────────────────────────────────────────────────
echo "──── Step 3: Notarize ────"
remaining_attempts=3
while [ "$remaining_attempts" -gt 0 ] ; do
    if "$SCRIPT_DIR/notarize.sh" --pkg-path "$OUTPUT_PKG" ; then
        break
    fi
    ((remaining_attempts -= 1))
    if [ "$remaining_attempts" -gt 0 ] ; then
        echo "Notarization failed. Wait before retrying ..."
        sleep 3
    else
        echo "Notarization failed. Exit"
        exit 1
    fi
done
echo ""

# ── Step 4 ────────────────────────────────────────────────────────────────────
echo "──── Step 4: Staple ────"
"$SCRIPT_DIR/staple_pkg.sh" --pkg-path "$OUTPUT_PKG" 2>/dev/null || {
    echo "Note: Stapling may not apply to PKGs; running notarization validation..."
    xcrun stapler validate "$OUTPUT_PKG" 2>/dev/null || true
}
echo ""

echo "╔══════════════════════════════════════════╗"
echo "║  Distribution complete                   ║"
echo "╠══════════════════════════════════════════╣"
echo "  $OUTPUT_PKG"
echo "╚══════════════════════════════════════════╝"
