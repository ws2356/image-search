#!/usr/bin/env bash
set -euo pipefail

# Bump macOS app version keys in dt_image_search/resources/AppInfo.plist.
# Usage:
#   bump_macos.sh --major
#   bump_macos.sh --minor
#   bump_macos.sh --patch
#
# Behavior:
# - Updates CFBundleShortVersionString and CFBundleVersion to the same value.
# - Commits only AppInfo.plist with message:
#     Bump macos version to: <version>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLIST_PATH="$REPO_ROOT/dt_image_search/resources/AppInfo.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

usage() {
    cat <<'EOF'
Usage: bump_macos.sh [--major | --minor | --patch]

Options:
  --major  Increase major by 1; reset minor/patch to 0
  --minor  Increase minor by 1; reset patch to 0
  --patch  Increase patch by 1
EOF
}

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    --major|--minor|--patch) ;;
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

[[ -f "$PLIST_PATH" ]] || { echo "Error: missing plist: $PLIST_PATH" >&2; exit 1; }
[[ -x "$PLIST_BUDDY" ]] || { echo "Error: missing PlistBuddy at $PLIST_BUDDY" >&2; exit 1; }

current_short="$("$PLIST_BUDDY" -c "Print :CFBundleShortVersionString" "$PLIST_PATH")"
current_bundle="$("$PLIST_BUDDY" -c "Print :CFBundleVersion" "$PLIST_PATH")"

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

case "$1" in
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

"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $next_version" "$PLIST_PATH"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $next_version" "$PLIST_PATH"
plutil -lint "$PLIST_PATH" >/dev/null

cd "$REPO_ROOT"
git add "$PLIST_PATH"

if git diff --cached --quiet -- "$PLIST_PATH"; then
    echo "No version change detected; nothing to commit."
    exit 0
fi

git commit -m "Bump macos version to: $next_version" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" \
    -- "$PLIST_PATH"

echo "Updated and committed macOS version: $next_version"
