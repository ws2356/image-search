#!/usr/bin/env bash
set -euo pipefail

# Creates a distributable DMG containing the .app and an /Applications symlink
# for drag-and-drop installation, then signs the DMG.
#
# Signing the DMG before notarization is recommended by Apple.
#
# Usage:
#   package_dmg.sh \
#       --app-path    ./pyinstaller-dist-prod/AuSearch.app \
#       --output      ./dist/AuSearch-1.2.3.dmg \
#       [--volume-name "AuSearch"] \
#       [--identity   "Developer ID Application: NAME (TEAMID)"]
#
# The signing identity may also be supplied via $DEVELOPER_ID_IDENTITY.
# Omit both to create an unsigned DMG (not recommended for distribution).

APP_PATH=""
VOLUME_NAME=""
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)    APP_PATH="$2";    shift 2 ;;
        --volume-name) VOLUME_NAME="$2"; shift 2 ;;
        --identity)    IDENTITY="$2";    shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH"   ]] && { echo "Error: --app-path is required" >&2; exit 1; }
[[ -d "$APP_PATH"   ]] || { echo "Error: .app not found: $APP_PATH" >&2; exit 1; }
[[ -z "$VOLUME_NAME" ]] && VOLUME_NAME="$(basename "$APP_PATH" .app)"

if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$(pwd)/$APP_PATH"
fi

OUTPUT_DMG="${APP_PATH}.dmg"

if [[ -f "$OUTPUT_DMG" ]]; then
    mv "$OUTPUT_DMG" "${OUTPUT_DMG}.bak"
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"

# ── Stage: .app + Applications symlink ───────────────────────────────────────
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "Staging at: $STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ── Create compressed DMG ─────────────────────────────────────────────────────
echo "Creating DMG: $OUTPUT_DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$OUTPUT_DMG"

# ── Sign the DMG ─────────────────────────────────────────────────────────────
if [[ -n "$IDENTITY" ]]; then
    echo "Signing DMG..."
    codesign --sign "$IDENTITY" --timestamp "$OUTPUT_DMG"
    echo "  Signed."
else
    echo "WARNING: No signing identity provided — DMG is unsigned."
    echo "         Set \$DEVELOPER_ID_IDENTITY or pass --identity."
fi

echo "Done: $OUTPUT_DMG"
