#!/bin/bash
# Terraform wrapper that fetches the Cloudflare API token from macOS keychain.
# Usage: bash scripts/deploy.sh plan
#        bash scripts/deploy.sh apply -var="origin_ip=1.2.3.4"
set -euo pipefail

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tf_dir="$(cd "$this_dir/.." && pwd)"

# Read cf_account_id from terraform.tfvars
account_id_line=$(grep -E '^\s*cf_account_id\s*=' "$tf_dir/terraform.tfvars" || true)
if [[ -z "$account_id_line" ]]; then
  echo "Error: cf_account_id not found in terraform.tfvars" >&2
  exit 1
fi
if [[ "$account_id_line" =~ ^[[:space:]]*cf_account_id[[:space:]]*=[[:space:]]*(\"|\')([^\"\']+)(\"|\') ]] && \
  [ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[3]}" ] ; then
  cf_account_id="${BASH_REMATCH[2]}"
else
  echo "Error: Could not parse cf_account_id from terraform.tfvars" >&2
  exit 1
fi

# Fetch API token from macOS keychain
echo "Fetching Cloudflare API token from keychain..." >&2
export TF_VAR_cf_api_token
TF_VAR_cf_api_token="$(security find-generic-password -s cloudflare-api-token -a "$cf_account_id" -w)"
if [ -z "$TF_VAR_cf_api_token" ]; then
  echo "Error: Could not find Cloudflare API token in keychain for account ID $cf_account_id" >&2
  exit 1
fi

cd "$tf_dir"

# Auto-init if needed
if [ ! -d .terraform ]; then
  echo "Running terraform init..." >&2
  terraform init
fi

terraform "$@"
