#!/usr/bin/env bash
set -euo pipefail

# Bump macOS app version keys in the plist corresponding to a product.
# Usage:
#   bump_macos.sh --product main --patch
#   bump_macos.sh --product snapget --minor
#   bump_macos.sh --product ext --major
#
# Behavior:
# - Updates CFBundleShortVersionString and CFBundleVersion to the same value.
# - Commits the plist with message:
#     Bump macos version to: <version>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

product=
bump=

declare -A PRODUCT_PLISTS=(
    [main]="$REPO_ROOT/dt_image_search/resources/AppInfo.plist"
    [snapget]="$REPO_ROOT/dt_image_search/resources/AppInfoInstantShare.plist"
    [ext]="$REPO_ROOT/macos/ShareExtension/Info.plist"
    [ios]="$REPO_ROOT/mobile/ios/App/Info.plist"
)

[[ -x "$PLIST_BUDDY" ]] || { echo "Error: missing PlistBuddy at $PLIST_BUDDY" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: bump_macos.sh --product <main|snapget|ext|ios> [--major | --minor | --patch]

Options:
  --product <product>  Select which product's plist to bump:
                       main  - AuSearch (AppInfo.plist)
                       snapget - SnapGet (AppInfoInstantShare.plist)
                       ext   - Share Extension (Info.plist)
                       ios   - iOS App (Info.plist)
  --major              Increase major by 1; reset minor/patch to 0
  --minor              Increase minor by 1; reset patch to 0
  --patch              Increase patch by 1
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --product)
            if [[ $# -lt 2 ]]; then
                echo "Error: --product requires an argument" >&2
                usage
                exit 1
            fi
            product="$2"
            shift 2
            ;;
        --major|--minor|--patch)
            bump="$1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$product" ]]; then
    echo "Error: --product is required" >&2
    usage
    exit 1
fi

if [[ -z "$bump" ]]; then
    echo "Error: one of --major, --minor, or --patch is required" >&2
    usage
    exit 1
fi

plist_path="${PRODUCT_PLISTS[$product]:-}"
if [[ -z "$plist_path" ]]; then
    echo "Error: unknown product '$product'. Valid values: main, snapget, ext, ios" >&2
    usage
    exit 1
fi

[[ -f "$plist_path" ]] || { echo "Error: missing plist: $plist_path" >&2; exit 1; }

current_short="$("$PLIST_BUDDY" -c "Print :CFBundleShortVersionString" "$plist_path")"
current_bundle="$("$PLIST_BUDDY" -c "Print :CFBundleVersion" "$plist_path")"

if [[ "$current_short" != "$current_bundle" ]]; then
    echo "Error: CFBundleShortVersionString ($current_short) != CFBundleVersion ($current_bundle)." >&2
    echo "Please align them first, then rerun." >&2
    exit 1
fi

if [[ ! "$current_short" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: unsupported version format '$current_short'. Expected X.Y.Z" >&2
    exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$bump" in
    --major)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
    --minor)
        minor=$((minor + 1))
        patch=0
        ;;
    --patch)
        patch=$((patch + 1))
        ;;
esac

next_version="${major}.${minor}.${patch}"

"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $next_version" "$plist_path"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $next_version" "$plist_path"
plutil -lint "$plist_path" >/dev/null

cd "$REPO_ROOT"
git add "$plist_path"

if git diff --cached --quiet -- "$plist_path"; then
    echo "No version change detected; nothing to commit."
    exit 0
fi

git commit -m "Bump $product macos version to: $next_version"

echo "Updated and committed $product macOS version: $next_version"
