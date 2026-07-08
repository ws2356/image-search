# Cloudflare CDN Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Terraform project at `web/terraform/` that manages Cloudflare DNS and SSL settings for `boldman.net`, with shell scripts for Terraform invocation and certificate management.

**Architecture:** Flat Terraform root module with one file per resource type. Cloudflare provider authenticated via API token fetched from macOS keychain. Origin cert deployment handled by separate bash scripts.

**Tech Stack:** Terraform (cloudflare/cloudflare provider), bash, macOS `security` CLI

## Global Constraints

- Cloudflare API token stored in macOS keychain under service name `cloudflare-api-token`
- Terraform state stored locally (no remote backend)
- SSL mode: Full (Strict)
- All file paths use forward slashes
- Scripts use `set -euo pipefail`

---

### Task 1: Create Terraform provider configuration

**Files:**
- Create: `web/terraform/main.tf`
- Create: `web/terraform/variables.tf`
- Create: `web/terraform/outputs.tf`

**Interfaces:**
- Produces: `var.cf_api_token` (string, sensitive) — consumed by provider
- Produces: `var.origin_ip` (string) — consumed by dns.tf in Task 2
- Produces: `var.zone_name` (string, default `"boldman.net"`) — consumed by dns.tf in Task 2

- [ ] **Step 1: Create `web/terraform/` directory**

```bash
mkdir -p web/terraform
```

- [ ] **Step 2: Write `web/terraform/main.tf`**

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

provider "cloudflare" {
  api_token = var.cf_api_token
}
```

- [ ] **Step 3: Write `web/terraform/variables.tf`**

```hcl
variable "cf_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "origin_ip" {
  description = "Public IP address of the origin server"
  type        = string
}

variable "zone_name" {
  description = "Cloudflare zone domain name"
  type        = string
  default     = "boldman.net"
}
```

- [ ] **Step 4: Write `web/terraform/outputs.tf`**

```hcl
output "zone_id" {
  description = "Cloudflare zone ID for boldman.net"
  value       = cloudflare_zone.boldman_net.id
}

output "nameservers" {
  description = "Cloudflare-assigned nameservers (update your registrar)"
  value       = cloudflare_zone.boldman_net.name_servers
}

output "test_record_fqdn" {
  description = "FQDN of the test A record"
  value       = cloudflare_record.test.hostname
}
```

- [ ] **Step 5: Verify files exist**

```bash
ls web/terraform/main.tf web/terraform/variables.tf web/terraform/outputs.tf
```

- [ ] **Step 6: Commit**

```bash
git add web/terraform/main.tf web/terraform/variables.tf web/terraform/outputs.tf
git commit -m "feat(terraform): add provider, variables, and outputs for Cloudflare"
```

---

### Task 2: Add DNS zone and test A record

**Files:**
- Create: `web/terraform/dns.tf`

**Interfaces:**
- Consumes: `var.zone_name` (string) — from variables.tf
- Consumes: `var.origin_ip` (string) — from variables.tf
- Produces: `cloudflare_zone.boldman_net` — consumed by ssl.tf in Task 3
- Produces: `cloudflare_record.test` — referenced by outputs.tf

- [ ] **Step 1: Write `web/terraform/dns.tf`**

```hcl
resource "cloudflare_zone" "boldman_net" {
  zone = var.zone_name
}

resource "cloudflare_record" "test" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "test"
  value   = var.origin_ip
  type    = "A"
  proxied = true
}
```

- [ ] **Step 2: Verify Terraform validates the configuration**

```bash
cd web/terraform && terraform init -backend=false && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add web/terraform/dns.tf
git commit -m "feat(terraform): add DNS zone and test A record"
```

---

### Task 3: Add SSL/TLS zone settings

**Files:**
- Create: `web/terraform/ssl.tf`

**Interfaces:**
- Consumes: `cloudflare_zone.boldman_net.id` — from dns.tf

- [ ] **Step 1: Write `web/terraform/ssl.tf`**

```hcl
resource "cloudflare_zone_settings_override" "boldman_net" {
  zone_id = cloudflare_zone.boldman_net.id

  settings {
    ssl                      = "strict"
    min_tls_version          = "1.2"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
  }
}
```

- [ ] **Step 2: Verify Terraform validates**

```bash
cd web/terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add web/terraform/ssl.tf
git commit -m "feat(terraform): add SSL/TLS zone settings (strict mode, TLS 1.2+)"
```

---

### Task 4: Create example tfvars file

**Files:**
- Create: `web/terraform/terraform.tfvars.example`

- [ ] **Step 1: Write `web/terraform/terraform.tfvars.example`**

```hcl
# Copy this file to terraform.tfvars and fill in values.
# Do NOT commit terraform.tfvars (it contains secrets).

cf_api_token = ""  # Fetched automatically by scripts/deploy.sh from keychain
origin_ip    = ""  # Public IP of the nginx origin server
```

- [ ] **Step 2: Add terraform.tfvars to .gitignore**

Create or update `web/terraform/.gitignore`:

```
.terraform/
*.tfstate
*.tfstate.backup
terraform.tfvars
.terraform.lock.hcl
```

- [ ] **Step 3: Commit**

```bash
git add web/terraform/terraform.tfvars.example web/terraform/.gitignore
git commit -m "chore(terraform): add example tfvars and gitignore"
```

---

### Task 5: Create Terraform wrapper script

**Files:**
- Create: `web/terraform/scripts/deploy.sh`

- [ ] **Step 1: Create scripts directory**

```bash
mkdir -p web/terraform/scripts
```

- [ ] **Step 2: Write `web/terraform/scripts/deploy.sh`**

```bash
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
```

- [ ] **Step 3: Make script executable**

```bash
chmod +x web/terraform/scripts/deploy.sh
```

- [ ] **Step 4: Commit**

```bash
git add web/terraform/scripts/deploy.sh
git commit -m "feat(terraform): add deploy.sh wrapper with keychain token fetch"
```

---

### Task 6: Create certificate import script

**Files:**
- Create: `web/terraform/scripts/import-cert.sh`

- [ ] **Step 1: Write `web/terraform/scripts/import-cert.sh`**

```bash
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
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x web/terraform/scripts/import-cert.sh
```

- [ ] **Step 3: Commit**

```bash
git add web/terraform/scripts/import-cert.sh
git commit -m "feat(terraform): add import-cert.sh for macOS keychain"
```

---

### Task 7: Create certificate deploy script

**Files:**
- Create: `web/terraform/scripts/deploy-cert.sh`

- [ ] **Step 1: Write `web/terraform/scripts/deploy-cert.sh`**

```bash
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
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x web/terraform/scripts/deploy-cert.sh
```

- [ ] **Step 3: Commit**

```bash
git add web/terraform/scripts/deploy-cert.sh
git commit -m "feat(terraform): add deploy-cert.sh to rsync cert to origin"
```

---

### Task 8: End-to-end validation

- [ ] **Step 1: Verify all files exist**

```bash
ls -la web/terraform/*.tf web/terraform/scripts/*.sh web/terraform/terraform.tfvars.example web/terraform/.gitignore
```

Expected: 8 files listed (main.tf, dns.tf, ssl.tf, variables.tf, outputs.tf, .gitignore, tfvars.example, plus 3 scripts)

- [ ] **Step 2: Run terraform init and validate**

```bash
cd web/terraform && terraform init -backend=false && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Verify scripts are executable**

```bash
test -x web/terraform/scripts/deploy.sh && test -x web/terraform/scripts/import-cert.sh && test -x web/terraform/scripts/deploy-cert.sh && echo "All scripts executable"
```

- [ ] **Step 4: Run terraform plan (dry run — requires keychain token)**

```bash
cd web/terraform && bash scripts/deploy.sh plan -var="origin_ip=203.0.113.1"
```

Expected: Plan shows 3 resources to create (zone, record, settings override). This requires the `cloudflare-api-token` keychain entry to exist.

- [ ] **Step 5: Final commit (if any changes from validation)**

```bash
git add -A && git commit -m "chore(terraform): final validation cleanup" --allow-empty
```
