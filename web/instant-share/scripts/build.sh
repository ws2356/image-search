#!/bin/bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
this_dir="$(cd "$(dirname "$this_file")" && pwd)"

cd "$this_dir/.."
pnpm install
pnpm run build

cd "$this_dir/../relay"
pnpm install
