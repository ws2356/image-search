#!/usr/bin/env bash
set -euo pipefail

# Recursively codesigns the .app bundle for macOS notarized distribution.
# Hardened Runtime is enabled on every binary (required by Apple notarization).
#
# Signing order (inside-out, without the deprecated --deep flag):
#   1. Nested .framework bundles — deepest path first
#   2. All remaining Mach-O binaries (dylibs, .so files, bare executables)
#   3. The outer .app bundle — with entitlements applied here
#   4. Verification with codesign --verify and spctl --assess
#
# Usage:
#   codesign_app.sh \
#       --app-path    ./pyinstaller-dist-prod/AuSearch.app \
#       [--identity   "Developer ID Application: NAME (TEAMID)"] \
#       [--entitlements ./AuSearch.entitlements]
#
# The signing identity may also be supplied via $DEVELOPER_ID_IDENTITY.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_PATH=""
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
ENTITLEMENTS="${SCRIPT_DIR}/AuSearch.entitlements"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)     APP_PATH="$2";     shift 2 ;;
        --identity)     IDENTITY="$2";     shift 2 ;;
        --entitlements) ENTITLEMENTS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$APP_PATH"   ]]  && { echo "Error: --app-path is required" >&2; exit 1; }
[[ -z "$IDENTITY"   ]]  && { echo "Error: signing identity required (--identity or \$DEVELOPER_ID_IDENTITY)" >&2; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { echo "Error: entitlements file not found: $ENTITLEMENTS" >&2; exit 1; }
[[ -d "$APP_PATH"   ]]  || { echo "Error: .app not found: $APP_PATH" >&2; exit 1; }

AGENT_BUNDLE_PATH="${APP_PATH}/Contents/Helpers/InstantShareAgent.app"
if [[ ! -d "$AGENT_BUNDLE_PATH" ]]; then
    echo "Error: expected agent bundle not found at $AGENT_BUNDLE_PATH" >&2
    exit 1
fi
 
echo "==> Main App:          $APP_PATH"
echo "==> Agent App:         $AGENT_BUNDLE_PATH"
echo "==> Identity:     $IDENTITY"
echo "==> Entitlements: $ENTITLEMENTS"

# ── Step 1: Sign .framework bundles, deepest path first ──────────────────────
echo ""
echo "Step 1: Signing .framework bundles..."
fw_count=0
while IFS= read -r -d '' fw; do
    echo "  framework: $fw"
    codesign --sign "$IDENTITY" --timestamp --options runtime --force "$fw"
    fw_count=$((fw_count + 1))
done < <(find "${APP_PATH}/Contents" -name "*.framework" -type d -print0 \
             | sort -rz)
echo "  ${fw_count} framework(s) signed."

# ── Step 2: Sign all remaining Mach-O files (skip framework internals) ───────
echo ""
echo "Step 2: Signing Mach-O binaries..."
bin_count=0
while IFS= read -r -d '' bin; do
    if file "$bin" 2>/dev/null | grep -qE "Mach-O"; then
        codesign --sign "$IDENTITY" \
                 --timestamp \
                 --options runtime \
                 --force \
                 "$bin" 2>/dev/null \
            || echo "  WARNING: could not sign '$bin' (skipping)"
        bin_count=$((bin_count + 1))
    fi
done < <(find "${APP_PATH}/Contents" -type f \
             -not -path "*\.framework/*" \
             -print0)
echo "  ${bin_count} binary/binaries signed."

# # ── Step 3: Sign the bundle with entitlements ─────────────────────
# echo ""
# echo "Step 3: Signing app and service binaries with entitlements..."
# for binary in "$APP_PATH/Contents/MacOS"/* "$AGENT_BUNDLE_PATH/Contents/MacOS"/*; do
#     if [[ -f "$binary" ]] && file "$binary" 2>/dev/null | grep -qE "Mach-O"; then
#         echo "  signing binary with entitlements: $binary"
#         codesign --sign "$IDENTITY" \
#                  --timestamp \
#                  --options runtime \
#                  --entitlements "$ENTITLEMENTS" \
#                  --force \
#                  "$binary" 2>/dev/null \
#             || echo "  WARNING: could not sign '$binary' (skipping)"
#     fi
# done

echo ""
echo "Step 3: Signing inner .app bundle"
codesign --sign "$IDENTITY" \
         --timestamp \
         --options runtime \
        --entitlements "$ENTITLEMENTS" \
         --force \
         "$AGENT_BUNDLE_PATH"
echo "  Inner bundle signed."

# ── Step 3b: Sign plug-in bundles ─────────────────────────────────────────────
SHARE_EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/ShareExtension.appex"
if [[ -d "$SHARE_EXTENSION_PATH" ]]; then
    echo ""
    echo "Step 3b: Signing ShareExtension.appex plug-in"
    SHARE_EXT_ENTITLEMENTS="${SCRIPT_DIR}/../macos/ShareExtension/ShareExtension.entitlements"
    if [[ -f "$SHARE_EXT_ENTITLEMENTS" ]]; then
        codesign --sign "$IDENTITY" \
                 --timestamp \
                 --options runtime \
                 --entitlements "$SHARE_EXT_ENTITLEMENTS" \
                 --force \
                 "$SHARE_EXTENSION_PATH"
    else
        codesign --sign "$IDENTITY" \
                 --timestamp \
                 --options runtime \
                 --force \
                 "$SHARE_EXTENSION_PATH"
    fi
    echo "  ShareExtension.appex signed."
fi

echo ""
echo "Step 4: Signing outer .app bundle"
codesign --sign "$IDENTITY" \
         --timestamp \
         --options runtime \
        --entitlements "$ENTITLEMENTS" \
         --force \
         "$APP_PATH"
echo "  Bundle signed."

# ── Step 5: Verify ────────────────────────────────────────────────────────────
echo ""
echo "Step 5: Verifying..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# spctl assessment only passes after notarization; print result without failing.
echo "  spctl pre-notarization check:"
spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1 \
    || echo "  (spctl rejection expected before notarization — that is normal)"

echo ""
echo "Codesigning complete."
