#!/usr/bin/env bash
set -euo pipefail

# Creates a signed distribution PKG installer from a signed .app bundle.
#
# The PKG installs the .app to /Applications and runs a postinstall script
# that installs and loads a LaunchAgent for the instant share daemon.
#
# Usage:
#   build_pkg.sh \
#       --app-path    ./pyinstaller-dist-prod/AuSearch.app \
#       --output      ./dist/AuSearch-1.2.3.pkg \
#       [--identity   "Developer ID Installer: NAME (TEAMID)"]
#
# The installer signing identity may also be supplied via
# $DEVELOPER_ID_INSTALLER (note: *Installer*, not *Application*).
#
# Required env (for notarization):
#   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#
# Requires:
#   - productbuild   (included with Xcode)
#   - productsign    (included with Xcode, optional if --identity omitted)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APP_PATH=""
OUTPUT_PKG=""
INSTALLER_IDENTITY="${DEVELOPER_ID_INSTALLER:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)    APP_PATH="$2";    shift 2 ;;
        --output)      OUTPUT_PKG="$2";  shift 2 ;;
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
OUTPUT_PKG="${OUTPUT_PKG:-$(dirname "$APP_PATH")/${APP_BUNDLE_NAME}.pkg}"
mkdir -p "$(dirname "$OUTPUT_PKG")"

# ── Scripts for PKG ────────────────────────────────────────────────────────────
PKG_SCRIPTS="$(mktemp -d)"
trap 'rm -rf "$PKG_SCRIPTS"' EXIT

mkdir -p "$PKG_SCRIPTS"
cp "$SCRIPT_DIR/pkg_scripts/postinstall" "$PKG_SCRIPTS/"
chmod +x "$PKG_SCRIPTS/postinstall"

# ── Distribution package ──────────────────────────────────────────────────────
# productbuild --component creates a flat distribution PKG that installs the
# .app bundle at /Applications with the postinstall script. This is simpler
# and more reliable than pkgbuild + productbuild --distribution.
echo "Creating distribution package..."
if [[ -n "$INSTALLER_IDENTITY" ]]; then
    productbuild \
        --component "$APP_PATH" "/Applications" \
        --scripts "$PKG_SCRIPTS" \
        --sign "$INSTALLER_IDENTITY" \
        "$OUTPUT_PKG"
else
    productbuild \
        --component "$APP_PATH" "/Applications" \
        --scripts "$PKG_SCRIPTS" \
        "$OUTPUT_PKG"
    echo "WARNING: No installer identity provided — PKG is unsigned."
    echo "         Set \$DEVELOPER_ID_INSTALLER or pass --identity."
    echo "         Note: This is the *Installer* identity, not the *Application* identity."
fi

echo ""
echo "Done: $OUTPUT_PKG"
