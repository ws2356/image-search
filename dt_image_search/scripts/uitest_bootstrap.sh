#!/bin/bash
set -euo pipefail

sync_deps=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sync-deps)
      sync_deps=true
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

if [ "$sync_deps" = true ]; then
    echo "Syncing Python dependencies..."
    uv sync --project "$PROJECT_ROOT" --frozen
fi

echo "Restoring Dotnet dependencies..."
dotnet restore "$PROJECT_ROOT/tests/integration/UIAutomationTests/UIAutomationTests.csproj"

echo "Bootstrap complete."
