#!/bin/bash
set -euo pipefail

pip_install=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pip-install)
      pip_install=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../.."

if [ "$pip_install" = true ]; then
    echo "Installing Python dependencies..."
    python -m pip install -r "$PROJECT_ROOT/requirements.txt"

    if [ -f "$PROJECT_ROOT/requirements-dev.txt" ]; then
        python -m pip install -r "$PROJECT_ROOT/requirements-dev.txt"
    fi
fi

echo "Restoring Dotnet dependencies..."
dotnet restore "$PROJECT_ROOT/tests/integration/UIAutomationTests/UIAutomationTests.csproj"

echo "Bootstrap complete."
