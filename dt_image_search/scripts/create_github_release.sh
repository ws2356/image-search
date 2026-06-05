#!/usr/bin/env bash
set -euo pipefail

# Create or update a GitHub release and upload a DMG asset.
#
# Usage:
#   create_github_release.sh \
#       --tag v1.2.3 \
#       --title "AuSearch v1.2.3" \
#       --notes-file ./release-notes.md \
#       --dmg-path ./pyinstaller-dist-prod/AuSearch.dmg \
#       [--repo ws2356/image-search] \
#       [--target main] \
#       [--draft] \
#       [--prerelease]

usage() {
    cat <<'EOF'
Create or update a GitHub release and upload a PKG or DMG asset.

Required:
  --tag <tag>               Release tag (for example: v1.2.3)
  --title <title>           Release title
  --pkg-path <path>         PKG file to upload
    or
  --dmg-path <path>         DMG file to upload (legacy)
  --notes <text>            Release notes text
    or
  --notes-file <path>       Release notes file path

Optional:
  --repo <owner/name>       Default: ws2356/image-search
  --target <branch|sha>     Create release from this target
  --draft                   Mark release as draft
  --prerelease              Mark release as prerelease
  -h, --help                Show this help
EOF
}

TAG=""
TITLE=""
NOTES=""
NOTES_FILE=""
ASSET_PATH=""
REPO="ws2356/image-search"
TARGET=""
DRAFT=false
PRERELEASE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --tag) TAG="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        --notes-file) NOTES_FILE="$2"; shift 2 ;;
        --dmg-path) ASSET_PATH="$2"; shift 2 ;;
        --pkg-path) ASSET_PATH="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --draft) DRAFT=true; shift ;;
        --prerelease) PRERELEASE=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$TAG" ]]; then
    echo "Error: --tag is required." >&2
    exit 1
fi
if [[ -z "$TITLE" ]]; then
    echo "Error: --title is required." >&2
    exit 1
fi
if [[ -z "$ASSET_PATH" ]]; then
    echo "Error: --pkg-path (or --dmg-path) is required." >&2
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
    echo "Release '$TAG' already exists in $REPO. Updating metadata and replacing DMG..."
    gh release edit "$TAG" "${EDIT_FLAGS[@]}" --title "$TITLE" "${NOTES_ARGS[@]}"
    gh release upload "$TAG" "$ASSET_PATH" --repo "$REPO" --clobber
else
    echo "Creating release '$TAG' in $REPO..."
    gh release create "$TAG" "$ASSET_PATH" "${COMMON_FLAGS[@]}" --title "$TITLE" "${NOTES_ARGS[@]}"
fi

echo "Release ready: $REPO@$TAG ($(basename "$ASSET_PATH"))"
