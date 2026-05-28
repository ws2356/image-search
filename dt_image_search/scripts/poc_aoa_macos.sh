#!/bin/bash

set -euo pipefail

this_script="$0"
if [[ "$this_script" != /* ]]; then
  this_script="$(pwd)/$this_script"
fi
repo_root="$(cd "$(dirname "$this_script")/../.." && pwd)"

cd "$repo_root"
export PYTHONPATH="${PYTHONPATH:-}${PYTHONPATH:+:}."

python -m dt_image_search.mobile.transport.poc.android_aoa_poc \
  --host-os macos \
  --simulate \
  --output-root dt_image_search/mobile/transport/poc/runs

