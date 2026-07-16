#!/usr/bin/env bash
set -euo pipefail

# Embed Build Metadata — copies the checked-in template into the app bundle
# and fills the __GIT_REVISION__ slot with the current git revision.
# Runs after "Copy Bundle Resources", before code signing. Never mutates the repo.

SRCROOT="${SRCROOT:?SRCROOT not set}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR not set}"
CONTENTS_FOLDER_PATH="${CONTENTS_FOLDER_PATH:?CONTENTS_FOLDER_PATH not set}"

TEMPLATE="${SRCROOT}/App/BuildMetadata.template.json"
DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/BuildMetadata.json"

if [[ ! -f "${TEMPLATE}" ]]; then
    echo "error: BuildMetadata template not found at ${TEMPLATE}" >&2
    exit 1
fi

REVISION="unknown"
if REPO_ROOT="$(git -C "${SRCROOT}" rev-parse --show-toplevel 2>/dev/null)"; then
    REVISION="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo "unknown")"
fi

mkdir -p "$(dirname "${DEST}")"
cp "${TEMPLATE}" "${DEST}"

if [[ "${REVISION}" == "unknown" ]]; then
    sed -i '' 's/__GIT_REVISION__/unknown/' "${DEST}"
else
    sed -i '' "s/__GIT_REVISION__/${REVISION}/" "${DEST}"
fi

python3 -c "import json; json.load(open('${DEST}'))" >/dev/null
echo "Embedded BuildMetadata revision: ${REVISION}"
