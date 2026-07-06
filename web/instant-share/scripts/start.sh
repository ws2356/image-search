#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
this_dir="$(cd "$(dirname "$this_file")" && pwd)"

cd "$this_dir/.."

node_modules/.bin/vite --mode dev --config "vite.config.ts" --host