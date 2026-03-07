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
release_port() {
  PORT=$1
  # 1. Detect OS
  OS_TYPE="$(uname)"

  case "$OS_TYPE" in
      Linux*)
          # Using fuser (standard on most distros)
          PID=$(lsof -t -i:"$PORT" 2>/dev/null || fuser "$PORT/tcp" 2>/dev/null)
          if [ -n "$PID" ]; then
              echo "Killing PID $PID"
              kill -SIGTERM $PID
          fi
          ;;
      Darwin*)
          # macOS uses lsof by default
          PID=$(lsof -t -i:"$PORT")
          if [ -n "$PID" ]; then
              echo "Killing PID $PID"
              kill -SIGTERM $PID
          fi
          ;;
      MINGW*|MSYS*|CYGWIN*)
          # Windows (Git Bash / MSYS2)
          # We find the PID using netstat and kill via taskkill
          PID=$(netstat -ano | grep ":$PORT " | awk '{print $5}' | head -n 1)
          if [ -n "$PID" ] && [ "$PID" != "0" ]; then
              echo "Killing PID $PID"
              taskkill //F //PID "$PID"
          fi
          ;;
      *)
          ;;
  esac
}
release_port 4723 || true
release_port 10100 || true

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