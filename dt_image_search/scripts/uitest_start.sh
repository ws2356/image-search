#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../.."

echo "Starting UI Automation Tests..."
dotnet test "$PROJECT_ROOT/tests/integration/UIAutomationTests/UIAutomationTests.csproj" --logger "console;verbosity=detailed"

echo "Tests complete."
