#!/bin/bash
# Terraform wrapper that fetches the Cloudflare API token from macOS keychain.
# Usage: bash scripts/deploy.sh plan
#        bash scripts/deploy.sh apply -var="origin_ip=1.2.3.4"
set -euo pipefail

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tf_dir="$(cd "$this_dir/.." && pwd)"

# Fetch API token from macOS keychain
echo "Fetching Cloudflare API token from keychain..." >&2
export TF_VAR_cf_api_token
TF_VAR_cf_api_token="$(security find-generic-password -s cloudflare-api-token -w)"

cd "$tf_dir"

# Auto-init if needed
if [ ! -d .terraform ]; then
  echo "Running terraform init..." >&2
  terraform init
fi

terraform "$@"
