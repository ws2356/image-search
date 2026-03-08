#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd -W)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

echo "Starting UI Automation Tests..."
export TEST_FOLDER="$PROJECT_ROOT/tests/assets/test-folder"
echo "Test folder set to: $TEST_FOLDER"
# Replace / with \ for Windows paths
export TEST_FOLDER="${TEST_FOLDER//\//\\}"
echo "Test folder set to: $TEST_FOLDER"
dotnet test "$PROJECT_ROOT/tests/integration/UIAutomationTests/UIAutomationTests.csproj" --logger "console;verbosity=detailed"

echo "Tests complete."
