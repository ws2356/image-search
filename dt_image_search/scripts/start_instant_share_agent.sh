#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
this_dir="$(dirname "$this_file")"

cd "$this_dir/../.."

export INSTANT_SHARE_QR_BASE_URL='http://192.168.50.17:5173'
export RELAY_URL='ws://192.168.50.17:8787/'
python -m dt_image_search.scripts.start_instant_share_gui_runtime --force-enable --log-level DEBUG