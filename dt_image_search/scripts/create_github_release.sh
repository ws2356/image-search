#!/usr/bin/env bash
set -euo pipefail

# Create or update a GitHub release, upload release asset, and track the
# release in releases.json (committed before tagging so that the tag commit
# includes the updated manifest).
#
# Usage:
#   create_github_release.sh \
#       --product main \
#       --tag v1.2.3 \
#       --title "AuSearch v1.2.3" \
#       --notes-file ./release-notes.md \
#       --asset-path ./pyinstaller-dist-prod/AuSearch.pkg \
#       [--target main] \
#       [--draft] \
#       [--prerelease]
#
# The tag is expected to follow the convention: <version>-<product>.
# releases.json lives at the repository root and is updated BEFORE tagging,
# so the tag commit always carries the latest release manifest.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RELEASES_JSON="$REPO_ROOT/releases.json"

usage() {
    cat <<'EOF'
Create or update a GitHub release, upload a PKG or DMG asset, and track the
release in releases.json.

Required:
  --product <main|snapget>
                         Product being released
  --tag <tag>            Release tag (format: <version>-<product>)
  --title <title>        Release title
  --asset-path <path>    PKG or DMG file to upload
  --notes <text>         Release notes text
    or
  --notes-file <path>    Release notes file path

Optional:
  --target <branch|sha>  Create release from this target
  --draft                Mark release as draft
  --prerelease           Mark release as prerelease
  -h, --help             Show this help
EOF
}

PRODUCT=""
TAG=""
TITLE=""
NOTES=""
NOTES_FILE=""
ASSET_PATH=""
TARGET=""
DRAFT=false
PRERELEASE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --product) PRODUCT="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        --notes-file) NOTES_FILE="$2"; shift 2 ;;
        --asset-path) ASSET_PATH="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --draft) DRAFT=true; shift ;;
        --prerelease) PRERELEASE=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PRODUCT" ]]; then
    echo "Error: --product is required (main or snapget)." >&2
    exit 1
fi
if [[ "$PRODUCT" != "main" && "$PRODUCT" != "snapget" ]]; then
    echo "Error: --product must be 'main' or 'snapget', got '$PRODUCT'." >&2
    exit 1
fi
if [[ -z "$TAG" ]]; then
    echo "Error: --tag is required." >&2
    exit 1
fi
if [[ -z "$TITLE" ]]; then
    echo "Error: --title is required." >&2
    exit 1
fi
if [[ -z "$ASSET_PATH" ]]; then
    echo "Error: --asset-path is required." >&2
    exit 1
fi
if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
    echo "Error: use either --notes or --notes-file, not both." >&2
    exit 1
fi
if [[ -z "$NOTES" && -z "$NOTES_FILE" ]]; then
    echo "Error: provide --notes or --notes-file." >&2
    exit 1
fi

if [[ "$ASSET_PATH" != /* ]]; then
    ASSET_PATH="$(pwd)/$ASSET_PATH"
fi
if [[ -n "$NOTES_FILE" && "$NOTES_FILE" != /* ]]; then
    NOTES_FILE="$(pwd)/$NOTES_FILE"
fi

[[ -f "$ASSET_PATH" ]] || { echo "Error: asset file not found: $ASSET_PATH" >&2; exit 1; }
if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || { echo "Error: notes file not found: $NOTES_FILE" >&2; exit 1; }
fi

command -v gh >/dev/null 2>&1 || {
    echo "Error: gh CLI is required." >&2
    exit 1
}
gh auth status >/dev/null 2>&1 || {
    echo "Error: gh is not authenticated. Run 'gh auth login' first." >&2
    exit 1
}

REPO="ws2356/image-search"
# ── Update releases.json before tagging ──────────────────────────────
ASSET_NAME="$(basename "$ASSET_PATH")"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET_NAME"

if [[ ! -f "$RELEASES_JSON" ]]; then
    echo "Error: releases.json not found at $RELEASES_JSON" >&2
    exit 1
fi

python3 -c "
import json
path = '$RELEASES_JSON'
with open(path) as f:
    data = json.load(f)
data['$PRODUCT'] = {
    'tag': '$TAG',
    'download_url': '$DOWNLOAD_URL'
}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

echo "Updated $RELEASES_JSON for $PRODUCT: $TAG"

# Commit releases.json so the tag commit includes the updated manifest
cd "$REPO_ROOT"
git add "$(basename "$RELEASES_JSON")"
if git diff --cached --quiet; then
    echo "No changes to releases.json; skipping commit."
else
    git commit -m "Update $PRODUCT release manifest: $TAG"
    echo "Committed releases.json update."
fi

# ── Tag and release ──────────────────────────────────────────────────
git tag "$TAG"
git push origin HEAD
git push origin "$TAG"

NOTES_ARGS=()
if [[ -n "$NOTES_FILE" ]]; then
    NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
    NOTES_ARGS=(--notes "$NOTES")
fi

COMMON_FLAGS=(--repo "$REPO")
EDIT_FLAGS=(--repo "$REPO")
if [[ "$DRAFT" == true ]]; then
    COMMON_FLAGS+=(--draft)
    EDIT_FLAGS+=(--draft)
fi
if [[ "$PRERELEASE" == true ]]; then
    COMMON_FLAGS+=(--prerelease)
    EDIT_FLAGS+=(--prerelease)
fi
if [[ -n "$TARGET" ]]; then
    COMMON_FLAGS+=(--target "$TARGET")
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release '$TAG' already exists in $REPO. Aborting to avoid overwriting. Use a different tag or delete the existing release first."
    exit 1
fi

echo "Creating release '$TAG' in $REPO..."
gh release create "$TAG" "$ASSET_PATH" "${COMMON_FLAGS[@]}" --title "$TITLE" "${NOTES_ARGS[@]}"

echo "Release ready: $REPO@$TAG ($ASSET_NAME)"
