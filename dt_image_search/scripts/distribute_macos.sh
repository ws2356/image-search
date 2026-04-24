#!/usr/bin/env bash
set -euo pipefail

# End-to-end macOS notarized distribution pipeline:
#   1. Patch Info.plist  (version, display name, local-network description)
#   2. Codesign .app     (Hardened Runtime, inside-out)
#   3. Package DMG       (.app + /Applications symlink, signed DMG)
#   4. Notarize DMG      (xcrun notarytool, waits for Accepted status)
#   5. Staple DMG        (embeds ticket for offline verification)
#
# Usage:
#   distribute_macos.sh \
#       --app-path  ./pyinstaller-dist-prod/AuSearch.app \
#       --version   1.2.3 \
#       --output    ./dist/AuSearch-1.2.3.dmg \
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

APP_PATH=""
VERSION=""
OUTPUT_DMG=""
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
SKIP_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)      APP_PATH="$2";   shift 2 ;;
        --version)       VERSION="$2";    shift 2 ;;
        --output)        OUTPUT_DMG="$2"; shift 2 ;;
        --identity)      IDENTITY="$2";   shift 2 ;;
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH"   ]] && { echo "Error: --app-path is required"  >&2; exit 1; }
[[ -z "$VERSION"    ]] && { echo "Error: --version is required"   >&2; exit 1; }
[[ -z "$OUTPUT_DMG" ]] && { echo "Error: --output is required"    >&2; exit 1; }

echo "╔══════════════════════════════════════════╗"
echo "║  macOS Distribution Pipeline             ║"
echo "╠══════════════════════════════════════════╣"
echo "  App:     $APP_PATH"
echo "  Version: $VERSION"
echo "  Output:  $OUTPUT_DMG"
[[ -n "$IDENTITY" ]] && echo "  Identity: $IDENTITY"
echo ""

# ── Step 1 ────────────────────────────────────────────────────────────────────
echo "──── Step 1: Patch Info.plist ────"
"$SCRIPT_DIR/setup_bundle_metadata.sh" \
    --app-path "$APP_PATH" \
    --version  "$VERSION"
echo ""

# ── Step 2 ────────────────────────────────────────────────────────────────────
echo "──── Step 2: Codesign ────"
SIGN_ARGS=(--app-path "$APP_PATH")
[[ -n "$IDENTITY" ]] && SIGN_ARGS+=(--identity "$IDENTITY")
"$SCRIPT_DIR/codesign_app.sh" "${SIGN_ARGS[@]}"
echo ""

# ── Step 3 ────────────────────────────────────────────────────────────────────
echo "──── Step 3: Package DMG ────"
VOLNAME="$(basename "$APP_PATH" .app)"
DMG_ARGS=(--app-path "$APP_PATH" --output "$OUTPUT_DMG" --volume-name "$VOLNAME")
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

# ── Step 4 ────────────────────────────────────────────────────────────────────
echo "──── Step 4: Notarize ────"
"$SCRIPT_DIR/notarize.sh" --dmg-path "$OUTPUT_DMG"
echo ""

# ── Step 5 ────────────────────────────────────────────────────────────────────
echo "──── Step 5: Staple ────"
"$SCRIPT_DIR/staple_dmg.sh" --dmg-path "$OUTPUT_DMG"
echo ""

echo "╔══════════════════════════════════════════╗"
echo "║  Distribution complete                   ║"
echo "╠══════════════════════════════════════════╣"
echo "  $OUTPUT_DMG"
echo "╚══════════════════════════════════════════╝"
