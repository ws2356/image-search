#!/bin/bash
# Deploy Cloudflare origin cert and key to the nginx origin server via SSH.
# Usage: bash scripts/deploy-cert.sh --ssh-target user@host <cert.pem> <key.pem>
set -euo pipefail

ssh_target=""
cert_pem=""
key_pem=""
: "${CERT_DEST_DIR:=/root/dl.boldman.net}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ssh-target)
      ssh_target="$2"
      shift 2
      ;;
    --dest-dir)
      CERT_DEST_DIR="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [ -z "$ssh_target" ]; then
  echo "Usage: $0 --ssh-target <user@host> [--dest-dir <path>] <cert.pem> <key.pem>" >&2
  exit 1
fi

cert_pem="${1:?Missing cert.pem argument}"
key_pem="${2:?Missing key.pem argument}"

if [ ! -f "$cert_pem" ] || [ ! -f "$key_pem" ]; then
  echo "Error: cert or key file not found" >&2
  exit 1
fi

echo "Deploying cert to ${ssh_target}:${CERT_DEST_DIR}/ ..." >&2
ssh "$ssh_target" "mkdir -p '$CERT_DEST_DIR'"
scp "$cert_pem" "${ssh_target}:${CERT_DEST_DIR}/cloudflare-origin-cert.pem"
scp "$key_pem" "${ssh_target}:${CERT_DEST_DIR}/cloudflare-origin-key.pem"

echo "Reloading nginx..." >&2
ssh "$ssh_target" "sudo nginx -s reload"

echo "Cert deployed and nginx reloaded." >&2
