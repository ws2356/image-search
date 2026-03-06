#!/bin/bash
set -euo pipefail

# list process that are running on ports 4723 and 10100 and kill them (Appium and the appium Mac2 driver)
lsof -i :4723 -t | xargs -r kill -SIGTERM || true
lsof -i :10100 -t | xargs -r kill -SIGTERM || true

# If macos
if [[ "$OSTYPE" == "darwin"* ]]; then
  # Check if mac2 driver is installed
  if ! npm list -g appium-mac2-driver > /dev/null 2>&1; then
    echo "Appium Mac2 driver is not installed. Installing..."
    npm install -g appium-mac2-driver
  fi
else
  node_modules/.bin/appium driver install windows
fi

node_modules/.bin/appium --use-plugins=inspector --allow-cors  --relaxed-security || true