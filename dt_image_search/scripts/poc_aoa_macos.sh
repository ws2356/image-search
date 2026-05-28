#!/bin/bash

set -euo pipefail

this_script="$0"
if [[ "$this_script" != /* ]]; then
  this_script="$(pwd)/$this_script"
fi
repo_root="$(cd "$(dirname "$this_script")/../.." && pwd)"

cd "$repo_root"
export PYTHONPATH="${PYTHONPATH:-}${PYTHONPATH:+:}."

mode="${1:-host}"
if [[ "$mode" != "host" && "$mode" != "simulate" ]]; then
  echo "Usage: $0 [host|simulate]"
  exit 1
fi

python -m dt_image_search.mobile.transport.poc.android_aoa_poc \
  --host-os macos \
  --mode "$mode" \
  --output-root dt_image_search/mobile/transport/poc/runs
