#!/usr/bin/env bash
# Default dev entry: the pywebview shell (spawns the index server + hosts the Vue3 UI).
set -euo pipefail
this_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(dirname "$this_dir")"
cd "$project_root"
exec uv run --frozen python -m dt_image_search.shell "$@"
