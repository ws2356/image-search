#!/bin/bash
set -euo pipefail

curl -X POST http://127.0.0.1:4723/session/42ae2585-75f5-44e0-b21a-51f546e89730/execute/sync \
  -H "Content-Type: application/json" \
  -d '{
    "script": "windows: click",
    "args": [
      {
        "elementId": "42.918978.4.-2147483626",
        "button": "right"
      }
    ]
  }'