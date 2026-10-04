#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$ROOT_DIR/tests/snapshot"
SNAPSHOT_DIR="$TEST_DIR/__Snapshots__"

MODE=test
TEST_FILTER=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -t|--test-id)
      TEST_FILTER="$2"
      shift ; shift
      ;;
    -r|--record)
      MODE="record"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-t <test-filter>] [-r]"
      echo ""
      echo "Options:"
      echo "  -t, --test-id    Run only tests matching this filter (e.g. 'test_pin_code_display')"
      echo "  -r, --record     Record snapshots (default is test mode)"
      echo "  -h, --help       Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                          # Run all snapshot tests"
      echo "  $0 -r                       # Record all snapshots"
      echo "  $0 -t test_pin_code         # Run only PIN code test"
      echo "  $0 -r -t test_qr            # Record QR code tests only"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Set environment variables
export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$ROOT_DIR"
export IS_TESTING=true

# Create snapshot directory if it doesn't exist
mkdir -p "$SNAPSHOT_DIR"

# Build pytest arguments
PYTEST_ARGS=()

if [[ "$MODE" == "record" ]]; then
    echo "==> Recording snapshots..."
    PYTEST_ARGS+=("--snapshot-update")
elif [[ "$MODE" == "test" ]]; then
    echo "==> Running snapshot tests..."
else
    echo "Invalid mode: $MODE" >&2
    echo "Usage: $0 [-t <test-filter>] [-r]" >&2
    exit 1
fi

# Add test filter if specified
if [[ -n "$TEST_FILTER" ]]; then
    PYTEST_ARGS+=("-k" "$TEST_FILTER")
fi

# Add test directory
PYTEST_ARGS+=("$TEST_DIR")

# Run pytest
echo "==> Running: uv run --project \"$ROOT_DIR\" --frozen ... python -m pytest ${PYTEST_ARGS[*]}"
uv run --project "$ROOT_DIR" --frozen --with pytest-qt --with pytest-snapshot python -m pytest "${PYTEST_ARGS[@]}" -v

# Print results
if [[ "$MODE" == "record" ]]; then
    echo ""
    echo "==> Snapshots recorded to: $SNAPSHOT_DIR"
    echo "==> To verify, run: $0"
else
    echo ""
    echo "==> All snapshot tests passed!"
fi
