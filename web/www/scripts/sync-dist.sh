#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_REMOTE_PATH="/var/www/html/aurora/"
REMOTE_PATH="${1:-${REMOTE_PATH:-${DEFAULT_REMOTE_PATH}}}"

cd "${WEB_DIR}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  pnpm run build
fi

rsync -avz --delete --exclude='.DS_Store' dist/ "tc:${REMOTE_PATH%/}/"
