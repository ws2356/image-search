#!/usr/bin/env bash
set -euo pipefail

# Builds the macOS ShareExtension.appex from Swift source using SwiftPM,
# then assembles the .appex bundle and codesigns it with the extension entitlements.
#
# Usage:
#   build_share_extension.sh \
#       [--app-path ./pyinstaller-dist-prod/AuSearch.app] \
#       [--identity "Developer ID Application: NAME (TEAMID)"] \
#       [--output-dir ./dist]
#
# If --app-path is given, the built .appex is copied into Contents/PlugIns/
# inside the .app bundle.
#
# The signing identity may also be supplied via $DEVELOPER_ID_IDENTITY.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APP_PATH=""
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)     APP_PATH="$2";     shift 2 ;;
        --identity)     IDENTITY="$2";     shift 2 ;;
        --output-dir)   OUTPUT_DIR="$2";   shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SHARED_EXTENSION_SRC="${REPO_ROOT}/macos/ShareExtension"
APPEX_NAME="ShareExtension.appex"

echo "==> Building ShareExtension from: $SHARED_EXTENSION_SRC"

# ── Step 1: Build with SwiftPM ─────────────────────────────────────────────────
(cd "$SHARED_EXTENSION_SRC" && swift build -c release --disable-sandbox)

BUILD_DIR="$SHARED_EXTENSION_SRC/.build/release"
BINARY_PATH="$BUILD_DIR/ShareExtension"
if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Error: Build succeeded but binary not found at $BINARY_PATH" >&2
    exit 1
fi

# ── Step 2: Assemble .appex bundle ─────────────────────────────────────────────
if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    APPEX_PATH="$OUTPUT_DIR/$APPEX_NAME"
else
    APPEX_PATH="$BUILD_DIR/$APPEX_NAME"
fi

rm -rf "$APPEX_PATH"
mkdir -p "$APPEX_PATH/Contents/MacOS"

cp "$BINARY_PATH" "$APPEX_PATH/Contents/MacOS/ShareExtension"
cp "$SHARED_EXTENSION_SRC/Info.plist" "$APPEX_PATH/Contents/Info.plist"

echo "  Bundle assembled at: $APPEX_PATH"

# ── Step 3: Codesign ───────────────────────────────────────────────────────────
ENTITLEMENTS="$SHARED_EXTENSION_SRC/ShareExtension.entitlements"
if [[ -n "$IDENTITY" ]]; then
    echo "  Signing with identity: $IDENTITY"
    codesign --sign "$IDENTITY" \
             --timestamp \
             --options runtime \
             --entitlements "$ENTITLEMENTS" \
             --force \
             "$APPEX_PATH"
    echo "  Signed."
else
    echo "  WARNING: No signing identity — skipping codesign."
    echo "  Set \$DEVELOPER_ID_IDENTITY or pass --identity."
fi

# ── Step 4: Copy into .app bundle if requested ─────────────────────────────────
if [[ -n "$APP_PATH" ]]; then
    PLUGINS_DIR="${APP_PATH}/Contents/PlugIns"
    mkdir -p "$PLUGINS_DIR"
    cp -R "$APPEX_PATH" "$PLUGINS_DIR/"
    echo "  Copied to: $PLUGINS_DIR/$APPEX_NAME"
fi

echo ""
echo "Build complete: $APPEX_PATH"
