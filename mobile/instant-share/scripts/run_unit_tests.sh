#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

should_clean=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean)
            should_clean=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--clean] [--help]"
            echo "Runs the unit tests for the Instant Share app."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

scheme=InstantShare
proj=InstantShare.xcodeproj

if [ "$should_clean" == true ] ; then
    xcodebuild clean -scheme "$scheme" -skipMacroValidation
fi

xcodebuild test \
    -project "$proj" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
    -only-testing:InstantShareTests \
    -skipMacroValidation
