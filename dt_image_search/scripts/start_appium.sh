#!/bin/bash
set -euo pipefail

this_file=$0
if [[ "${this_file}" != /* ]] ; then
  this_file="$(pwd)/$this_file"
fi

this_dir="$(dirname "$this_file")"

wd=${this_dir}/..
repo_root=${this_dir}/../..

cd "$wd"

# list process that are running on ports 4723 and 10100 and kill them (Appium and the appium Mac2 driver)
lsof -i :4723 -t | xargs -r kill -SIGTERM || true
lsof -i :10100 -t | xargs -r kill -SIGTERM || true

# If macos
if [[ "$OSTYPE" == "darwin"* ]]; then
  # Check if mac2 driver is installed
  if ! pnpm list -g appium-mac2-driver > /dev/null 2>&1; then
    echo "Appium Mac2 driver is not installed. Installing..."
    pnpm install -g appium-mac2-driver
  fi
else
  "$repo_root/node_modules/.bin/appium" driver install windows
fi

"$repo_root/node_modules/.bin/appium" --use-plugins=inspector --allow-cors  --relaxed-security || true