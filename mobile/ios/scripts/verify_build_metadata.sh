#!/usr/bin/env bash
set -euo pipefail

# Verify that a built .app contains BuildMetadata.json with a 40-char GitRevision.
# Usage: verify_build_metadata.sh <path-to-App.app>

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
    echo "usage: verify_build_metadata.sh <path-to-App.app>" >&2
    exit 2
fi

PLIST="${APP_PATH}/BuildMetadata.json"
if [[ ! -f "${PLIST}" ]]; then
    echo "error: BuildMetadata.json missing from ${APP_PATH}" >&2
    exit 1
fi

REVISION="$(python3 -c "import json,sys; print(json.load(open('${PLIST}')).get('GitRevision',''))" 2>/dev/null || echo "")"
if [[ ! "${REVISION}" =~ ^[0-9a-f]{40}$ ]] && [[ "${REVISION}" != "unknown" ]]; then
    echo "error: GitRevision is not a 40-char hash or 'unknown': '${REVISION}'" >&2
    exit 1
fi

echo "OK: BuildMetadata.json present, GitRevision=${REVISION}"
