#!/usr/bin/env bash
set -euo pipefail

# Recursively codesigns the .app bundle for macOS notarized distribution.
# Hardened Runtime is enabled on every binary (required by Apple notarization).
#
# Signing order (inside-out, without the deprecated --deep flag):
#   Detects which sub-bundles (InstantShareAgent, ShareExtension) exist
#   inside the .app and signs them as needed.
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
SHARE_EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/ShareExtension.appex"

echo "==> Main App:          $APP_PATH"
if [[ -d "$AGENT_BUNDLE_PATH" ]]; then
    echo "==> Agent App:         $AGENT_BUNDLE_PATH"
fi
if [[ -d "$SHARE_EXTENSION_PATH" ]]; then
    echo "==> Share Extension:   $SHARE_EXTENSION_PATH"
fi
echo "==> Identity:          $IDENTITY"
echo "==> Entitlements:      $ENTITLEMENTS"

# ── codesign_bundle: reusable function to codesign an entire bundle ──────────
# Usage:
#   codesign_bundle <bundle-path> [--entitlements <path>] [--exclude <path>]...
#
# Signs all .framework bundles (deepest path first), all Mach-O binaries, and
# then the bundle itself. Sub-bundles listed via --exclude are excluded from
# internal framework/binary searches so they are not double-signed.
codesign_bundle() {
    local bundle_path=""
    local entitlements_path=""
    local exclude_paths=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --entitlements) entitlements_path="$2"; shift 2 ;;
            --exclude)      exclude_paths+=("$2");   shift 2 ;;
            *)
                [[ -z "$bundle_path" ]] || { echo "Error: unexpected argument: $1" >&2; return 1; }
                bundle_path="$1"; shift
                ;;
        esac
    done

    [[ -n "$bundle_path" ]] || { echo "Error: codesign_bundle requires a bundle path" >&2; return 1; }
    [[ -d "$bundle_path" ]] || { echo "Error: bundle not found: $bundle_path" >&2; return 1; }

    local bundle_name
    bundle_name="$(basename "$bundle_path")"

    echo ""
    echo "--- codesign_bundle: $bundle_name ---"

    # ── Step A: Sign .framework bundles, deepest path first ──
    echo "  Signing frameworks..."
    local fw_count=0
    while IFS= read -r -d '' fw; do
        # Skip paths inside any --exclude bundle
        local skip=false
        for ep in "${exclude_paths[@]}"; do
            if [[ "$fw" == "$ep"* ]]; then
                skip=true
                break
            fi
        done
        $skip && continue

        echo "    framework: $fw"
        if ! codesign --sign "$IDENTITY" --timestamp --options runtime --force "$fw"; then
            echo "Error: failed to sign framework: $fw" >&2
            return 1
        fi
        fw_count=$((fw_count + 1))
    done < <(find "${bundle_path}/Contents" -name "*.framework" -type d -print0 \
                 | sort -rz)
    echo "    $fw_count framework(s) signed."

    # ── Step B: Sign all remaining Mach-O files ──
    # Exclude framework internals and paths inside any --exclude bundle.
    echo "  Signing Mach-O binaries..."
    local bin_count=0
    while IFS= read -r -d '' bin; do
        # Skip paths inside any --exclude bundle
        local skip=false
        for ep in "${exclude_paths[@]}"; do
            if [[ "$bin" == "$ep"* ]]; then
                skip=true
                break
            fi
        done
        $skip && continue

        if file "$bin" 2>/dev/null | grep -qE "Mach-O"; then
            if ! codesign --sign "$IDENTITY" \
                     --timestamp \
                     --options runtime \
                     --force \
                     "$bin" 2>/dev/null ; then
                echo "Error: failed to sign binary: $bin" >&2
                return 1
            fi
            bin_count=$((bin_count + 1))
        fi
    done < <(find "${bundle_path}/Contents" -type f \
                 -not -path "*\.framework/*" \
                 -print0)
    echo "    $bin_count binary/binaries signed."

    # ── Step C: Sign the bundle itself ──
    echo "  Signing bundle: $bundle_name"
    local sign_args=(
        --sign "$IDENTITY"
        --timestamp
        --options runtime
        --force
    )
    [[ -n "$entitlements_path" ]] && sign_args+=(--entitlements "$entitlements_path")
    if ! codesign "${sign_args[@]}" "$bundle_path" ; then
        echo "Error: failed to sign bundle: $bundle_path" >&2
        return 1
    fi
    echo "    Bundle signed."
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ── Step 1: Sign launch agent bundle (if present) ──────────────────────────
if [[ -d "$AGENT_BUNDLE_PATH" ]]; then
    echo ""
    echo "================================================================================"
    echo "Step 1: codesign_bundle launch_agent_bundle"
    echo "================================================================================"
    AGENT_ENTITLEMENTS="${SCRIPT_DIR}/AuSearchInstantShareAgent.entitlements"
    if [[ ! -f "$AGENT_ENTITLEMENTS" ]]; then
        echo "Error: agent entitlements not found: $AGENT_ENTITLEMENTS" >&2
        exit 1
    fi
    tmp_agent_bundle_path="${tmp_dir}/InstantShareAgent.app"
    mv "$AGENT_BUNDLE_PATH" "$tmp_agent_bundle_path"
    if codesign_bundle "$tmp_agent_bundle_path" --entitlements "$AGENT_ENTITLEMENTS" ; then
        mv "$tmp_agent_bundle_path" "$AGENT_BUNDLE_PATH"
    else
        mv "$tmp_agent_bundle_path" "$AGENT_BUNDLE_PATH"
        exit 1
    fi
else
    echo ""
    echo "No InstantShareAgent sub-bundle found — skipping."
fi

# ── Step 2: Sign share extension (if present) ──────────────────────────────
if [[ -d "$SHARE_EXTENSION_PATH" ]]; then
    echo ""
    echo "================================================================================"
    echo "Step 2: codesign_bundle share_extension"
    echo "================================================================================"
    _configuration="$(printf "%s" "${CONFIGURATION:-release}" | tr '[:upper:]' '[:lower:]')"
    SHARE_EXT_ENTITLEMENTS="$(cd "$SCRIPT_DIR/../../macos/ShareExtension" && pwd)/ShareExtension.${_configuration}.entitlements"
    if [[ ! -f "$SHARE_EXT_ENTITLEMENTS" ]]; then
        echo "Error: share extension entitlements not found: $SHARE_EXT_ENTITLEMENTS" >&2
        exit 1
    fi
    tmp_share_extension_path="${tmp_dir}/InstantShareExtension.appex"
    mv "$SHARE_EXTENSION_PATH" "$tmp_share_extension_path"
    if codesign_bundle "$tmp_share_extension_path" --entitlements "$SHARE_EXT_ENTITLEMENTS" ; then
        mv "$tmp_share_extension_path" "$SHARE_EXTENSION_PATH"
    else
        mv "$tmp_share_extension_path" "$SHARE_EXTENSION_PATH"
        exit 1
    fi
else
    echo ""
    echo "No ShareExtension.appex found — skipping."
fi

# ── Step 3: Sign main app bundle (excluding already-signed sub-bundles) ───────
echo ""
echo "================================================================================"
echo "Step 3: codesign_bundle main_app_bundle (excluding sub-bundles)"
echo "================================================================================"
SIGN_EXCLUDES=()
[[ -d "$AGENT_BUNDLE_PATH" ]]    && SIGN_EXCLUDES+=(--exclude "$AGENT_BUNDLE_PATH")
[[ -d "$SHARE_EXTENSION_PATH" ]] && SIGN_EXCLUDES+=(--exclude "$SHARE_EXTENSION_PATH")
codesign_bundle "$APP_PATH" \
    --entitlements "$ENTITLEMENTS" \
    "${SIGN_EXCLUDES[@]}"

# ── Step 4: Verify ────────────────────────────────────────────────────────────
echo ""
echo "================================================================================"
echo "Step 4: Verify main app bundle"
echo "================================================================================"
echo ""
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "  spctl pre-notarization check:"
spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1 \
    || echo "  (spctl rejection expected before notarization — that is normal)"

echo ""
echo "Codesigning complete."
