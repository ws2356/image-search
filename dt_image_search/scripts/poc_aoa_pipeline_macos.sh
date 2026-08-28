#!/bin/bash

set -euo pipefail

this_script="$0"
if [[ "$this_script" != /* ]]; then
  this_script="$(pwd)/$this_script"
fi
repo_root="$(cd "$(dirname "$this_script")/../.." && pwd)"

mode="${1:-host}"
runs_root="${2:-dt_image_search/mobile/transport/poc/runs}"
required_hosts="${3:-macos}"

if [[ "$mode" != "host" && "$mode" != "simulate" ]]; then
  echo "Usage: $0 [host|simulate] [runs_root] [required_hosts]"
  exit 1
fi

cd "$repo_root"
export PYTHONPATH="${PYTHONPATH:-}${PYTHONPATH:+:}."

python -m dt_image_search.mobile.transport.poc.android_aoa_poc \
  --host-os macos \
  --mode "$mode" \
  --output-root "$runs_root"

python -m dt_image_search.mobile.transport.poc.summarize_aoa_runs \
  --runs-root "$runs_root"

python -m dt_image_search.mobile.transport.poc.poc_aoa_gate \
  --runs-root "$runs_root" \
  --required-hosts "$required_hosts"

