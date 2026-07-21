#!/usr/bin/env bash
set -euo pipefail

# Creates a signed distribution PKG installer from a signed .app bundle.
#
# The PKG installs the .app to /Applications and runs a postinstall script
# that installs and loads a LaunchAgent for the instant share daemon.
#
# Usage:
#   package_pkg.sh \
#       --app-path    ./pyinstaller-dist-prod/AuSearch.app \
#       [--identity   "Developer ID Installer: NAME (TEAMID)"]
#
# The installer signing identity may also be supplied via
# $DEVELOPER_ID_INSTALLER (note: *Installer*, not *Application*).
#
# Required env (for notarization):
#   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#
# Requires:
#   - pkgbuild       (included with Xcode)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APP_PATH=""
INSTALLER_IDENTITY="${DEVELOPER_ID_INSTALLER:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)    APP_PATH="$2";    shift 2 ;;
        --identity)    INSTALLER_IDENTITY="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH"   ]] && { echo "Error: --app-path is required"  >&2; exit 1; }
[[ -d "$APP_PATH"   ]] || { echo "Error: .app not found: $APP_PATH" >&2; exit 1; }

if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$(pwd)/$APP_PATH"
fi

APP_BUNDLE_NAME="$(basename "$APP_PATH" .app)"
OUTPUT_PKG="$(dirname "$APP_PATH")/${APP_BUNDLE_NAME}.pkg"
mkdir -p "$(dirname "$OUTPUT_PKG")"

# Check for ShareExtension.appex (present in instant-share builds, absent in main-app)
SHARE_EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/ShareExtension.appex"
if [[ -d "$SHARE_EXTENSION_PATH" ]]; then
    echo "  ShareExtension.appex found at $SHARE_EXTENSION_PATH"
else
    echo "  Note: No ShareExtension.appex — this is expected for main-app builds."
fi

# ── Scripts for PKG ────────────────────────────────────────────────────────────
PKG_SCRIPTS="$(mktemp -d)"
trap 'rm -rf "$PKG_SCRIPTS"' EXIT

mkdir -p "$PKG_SCRIPTS"
cp "$SCRIPT_DIR/pkg_scripts/postinstall" "$PKG_SCRIPTS/"
chmod +x "$PKG_SCRIPTS/postinstall"

# ── Flat component package ─────────────────────────────────────────────────────
# pkgbuild --component with --install-location creates a flat component package
# that directly installs the .app at /Applications. Unlike productbuild, this
# does NOT wrap the package in a Distribution XML, avoiding the
# bundle-version/path conflict that caused previous PKGs to silently fail.
echo "Creating flat component package..."

if [[ -z "$INSTALLER_IDENTITY" ]]; then
    echo "WARNING: No installer identity provided — PKG is unsigned."
    echo "         Set \$DEVELOPER_ID_INSTALLER or pass --identity."
    echo "         Note: This is the *Installer* identity, not the *Application* identity."
fi

pkgbuild \
    --component "$APP_PATH" \
    --install-location "/Applications" \
    --scripts "$PKG_SCRIPTS" \
    --ownership recommended \
    --sign "$INSTALLER_IDENTITY" \
    "$OUTPUT_PKG"


echo ""
echo "Done: $OUTPUT_PKG"
