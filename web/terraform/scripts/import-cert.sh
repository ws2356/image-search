#!/bin/bash
# Import a Cloudflare Origin Certificate PEM into macOS login keychain.
# Usage: bash scripts/import-cert.sh <cert.pem> <key.pem>
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cert.pem> <key.pem>" >&2
  exit 1
fi

cert_pem="$1"
key_pem="$2"

if [ ! -f "$cert_pem" ] || [ ! -f "$key_pem" ]; then
  echo "Error: cert or key file not found" >&2
  exit 1
fi

# Create a temporary PKCS12 bundle
tmp_p12="$(mktemp /tmp/cf-cert-XXXXXX.p12)"
trap 'rm -f "$tmp_p12"' EXIT

echo "Creating PKCS12 bundle..." >&2
openssl pkcs12 -export \
  -in "$cert_pem" \
  -inkey "$key_pem" \
  -out "$tmp_p12" \
  -passout pass:

echo "Importing into login keychain..." >&2
security import "$tmp_p12" \
  -k ~/Library/Keychains/login.keychain-db \
  -t cert \
  -f pkcs12 \
  -P "" \
  -A

echo "Certificate imported successfully." >&2
