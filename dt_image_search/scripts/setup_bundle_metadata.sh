#!/usr/bin/env bash
set -euo pipefail

# Patches the Info.plist inside the generated .app bundle to set version
# numbers, display name, and the local-network privacy description.
#
# IMPORTANT: run this BEFORE codesign_app.sh.  Modifying Info.plist after
# signing invalidates the code signature.
#
# Usage:
#   setup_bundle_metadata.sh \
#       --app-path  ./pyinstaller-dist-prod/AuSearch.app \
#       --version   1.2.3 \
#       [--build-num 42]   (defaults to --version)

APP_PATH=""
VERSION=""
BUILD_NUM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)  APP_PATH="$2";  shift 2 ;;
        --version)   VERSION="$2";   shift 2 ;;
        --build-num) BUILD_NUM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH" ]] && { echo "Error: --app-path is required" >&2; exit 1; }
[[ -z "$VERSION"  ]] && { echo "Error: --version is required"  >&2; exit 1; }
[[ -z "$BUILD_NUM" ]] && BUILD_NUM="$VERSION"

PLIST="${APP_PATH}/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "Error: Info.plist not found: $PLIST" >&2; exit 1; }

PB=/usr/libexec/PlistBuddy

echo "Patching $PLIST (version $VERSION, build $BUILD_NUM)"

# Version numbers — PyInstaller creates these keys; update them.
"$PB" -c "Set :CFBundleShortVersionString $VERSION"  "$PLIST"
"$PB" -c "Set :CFBundleVersion $BUILD_NUM"            "$PLIST"

# Display name — add if missing, update if present.
"$PB" -c "Add :CFBundleDisplayName string AuSearch"   "$PLIST" 2>/dev/null \
    || "$PB" -c "Set :CFBundleDisplayName AuSearch"   "$PLIST"

# Local-network privacy string (required for macOS 10.15+).
# Note: NSBonjourServices should also be added here if the app advertises
# Bonjour services (e.g. _http._tcp).  Add as an array of service type
# strings if needed.
LN_DESC="AuSearch uses your local network to receive photo backups from your iPhone."
"$PB" -c "Add :NSLocalNetworkUsageDescription string ${LN_DESC}"  "$PLIST" 2>/dev/null \
    || "$PB" -c "Set :NSLocalNetworkUsageDescription ${LN_DESC}"  "$PLIST"

echo "Done."
