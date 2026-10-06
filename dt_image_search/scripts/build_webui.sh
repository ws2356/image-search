#!/usr/bin/env bash
# -- Build the Vue web UI served by the index server from inside packaged bundles
set -euo pipefail

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
webui_dir="$(cd "$this_dir/../webui" && pwd)"

# node lives under nvm in non-interactive shells; source it when available.
if [ -f "$HOME/.nvm/nvm.sh" ] && ! command -v node >/dev/null 2>&1; then
    . "$HOME/.nvm/nvm.sh"
fi
command -v node >/dev/null 2>&1 || { echo "Error: node not found in PATH" >&2; exit 1; }

# corepack ships with node and reads "packageManager" from package.json, so the
# persona manager version stays pinned without a global pnpm install.
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
pnpm_cmd=""
if command -v pnpm >/dev/null 2>&1; then
    pnpm_cmd="pnpm"
elif command -v corepack >/dev/null 2>&1; then
    pnpm_cmd="corepack pnpm"
else
    echo "Error: neither pnpm nor corepack found in PATH" >&2
    exit 1
fi

cd "$webui_dir"
echo "==> Installing webui dependencies ($pnpm_cmd)"
$pnpm_cmd install --frozen-lockfile
echo "==> Building webui (vite build)"
$pnpm_cmd run build

if [ ! -f "$webui_dir/dist/index.html" ]; then
    echo "Error: webui build did not produce dist/index.html" >&2
    exit 1
fi
echo "==> Web UI built at $webui_dir/dist"
