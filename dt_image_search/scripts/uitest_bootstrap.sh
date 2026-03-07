#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../.."

echo "Installing Python dependencies..."
pip install -r "$PROJECT_ROOT/requirements.txt"

if [ -f "$PROJECT_ROOT/requirements-dev.txt" ]; then
    pip install -r "$PROJECT_ROOT/requirements-dev.txt"
fi

echo "Restoring Dotnet dependencies..."
dotnet restore "$PROJECT_ROOT/tests/integration/UIAutomationTests/UIAutomationTests.csproj"

echo "Bootstrap complete."
