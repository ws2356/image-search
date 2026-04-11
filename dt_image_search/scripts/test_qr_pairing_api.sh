#!/bin/bash
set -euo pipefail

host="${1:-192.168.50.17}"
port="${2}"

ENDPOINT="http://${host}:${port}/api/mobile/pairing/claim"
SID='b3482273dd63470e837eae7dd362c7dc'
OPT='653624'

curl -v -i "$ENDPOINT" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-raw "{
    \"schema\":\"dtis.mobile-pairing.v1\",
    \"sid\":\"$SID\",
    \"opt\":\"$OPT\",
    \"platform\":\"ios\",
    \"device_uuid\":\"ios-curl-fregrttest-001\",
    \"device_name\":\"Curl Test iPhone\",
    \"client_nonce\":\"curl-test-001\"
  }"