#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
WEB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_REMOTE_PATH="/var/www/html/aurora/"
REMOTE_PATH="${1:-${REMOTE_PATH:-${DEFAULT_REMOTE_PATH}}}"
release_json="$repo_root/releases.json"

cd "${WEB_DIR}"

download_main="$(python3 -c "import json; print(json.load(open('$release_json'))['main']['download_url'])")"
download_is="$(python3 -c "import json; print(json.load(open('$release_json'))['snapget']['download_url'])")"

cp .env.example .env
sed -i '' "s|AUSEARCH_MACOS_DOWNLOAD_URL=.*|AUSEARCH_MACOS_DOWNLOAD_URL=\"$download_main\"|" .env && \
sed -i '' "s|INSTANTSHARE_MACOS_DOWNLOAD_URL=.*|INSTANTSHARE_MACOS_DOWNLOAD_URL=\"$download_is\"|" .env && \

pnpm run build

rsync -avz --delete --exclude='.DS_Store' dist/ "tc:${REMOTE_PATH%/}/"
