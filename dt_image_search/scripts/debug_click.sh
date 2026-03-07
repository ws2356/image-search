#!/bin/bash
set -euo pipefail

curl -X POST http://pc.home:4723/session/18ab6e79-527d-4bda-9532-7dea4ebae614/execute/sync \
  -H "Content-Type: application/json" \
  -d '{"script":"windows: click","args":[{"elementId":"42.198274.4.-2147483626","button":"right"}]}'