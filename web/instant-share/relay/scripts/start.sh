#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
this_dir="$(cd "$(dirname "$this_file")" && pwd)"
relay_dir="$this_dir/.."

node "$relay_dir/relay.mjs" "$@"