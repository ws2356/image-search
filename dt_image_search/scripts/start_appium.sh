#!/bin/bash
set -euo pipefail

# list process that are running on ports 4723 and 10100 and kill them (Appium and the appium Mac2 driver)
lsof -i :4723 -t | xargs -r kill -SIGTERM || true
lsof -i :10100 -t | xargs -r kill -SIGTERM || true

node_modules/.bin/appium --use-plugins=inspector --allow-cors  --relaxed-security || true