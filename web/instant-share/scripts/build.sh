#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pnpm install
pnpm run build
echo "Built dist/"
