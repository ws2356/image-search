# Cloudflare CDN Terraform Project Design

## Overview

Add a Terraform project to manage Cloudflare as a reverse proxy (CDN) in front of the existing nginx origin server for the instant-share web app. Cloudflare terminates TLS at the edge and re-encrypts to origin using Full (Strict) mode with a Cloudflare Origin Certificate.

## Current State

- nginx on `dl.boldman.net` serves:
  - Static SPA assets at `/share/` from `/var/www/html/instant-share/`
  - WebSocket relay at `/relay` proxied to `127.0.0.1:8787`
- SSL handled by nginx with certs on the server
- Deploy script: `web/instant-share/scripts/deploy.sh` (rsync + SSH)

## Architecture

```
Browser
    │
    │ HTTPS
    ▼
Cloudflare Edge (TLS termination, caching, DDoS protection)
    │
    │ HTTPS (Cloudflare Origin Certificate)
    ▼
nginx (port 443)
    ├── /share/ → static files
    └── /relay  → proxy_pass http://127.0.0.1:8787 (WebSocket upgrade)
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| SSL mode | Full (Strict) | Most secure; validates origin cert |
| Cloudflare plan | Free | WebSockets supported; sufficient for this use case |
| Terraform state | Local file | Simple for single developer; can migrate later |
| Origin cert mgmt | Separate bash scripts | Keeps Terraform focused on infra; cert deployment is an operational concern |

## Directory Structure

```
web/terraform/
├── main.tf                    # Cloudflare provider, required_providers
├── dns.tf                     # DNS zone, A records
├── ssl.tf                     # Zone SSL settings override
├── variables.tf               # Input variables
├── outputs.tf                 # Zone ID, nameservers, record FQDNs
├── terraform.tfvars.example   # Example variable values
└── scripts/
    ├── deploy.sh              # Terraform wrapper (fetches token from keychain)
    ├── import-cert.sh         # Import CF origin cert PEM to macOS keychain
    └── deploy-cert.sh         # Rsync cert+key to origin server via SSH
```

## Terraform Resources

### main.tf
- `terraform` block with required_providers for `cloudflare/cloudflare`
- `provider "cloudflare"` with `api_token` from `var.cf_api_token`

### dns.tf
- `cloudflare_zone.boldman_net` — zone for `boldman.net`
- `cloudflare_record.test` — A record: `test.boldman.net` → `var.origin_ip`, proxied=true

### ssl.tf
- `cloudflare_zone_settings_override.boldman_net`:
  - `ssl = "strict"`
  - `min_tls_version = "1.2"`
  - `always_use_https = "on"`
  - `automatic_https_rewrites = "on"`

### variables.tf
- `cf_api_token` (string, sensitive, no default)
- `origin_ip` (string, no default)
- `zone_name` (string, default `"boldman.net"`)

### outputs.tf
- `zone_id` — Cloudflare zone ID
- `nameservers` — assigned nameservers (to update at registrar)
- `test_record_fqdn` — FQDN of the test A record

## Scripts

### scripts/deploy.sh
Terraform wrapper that:
1. Fetches CF API token: `security find-generic-password -s cloudflare-api-token -w`
2. Exports `TF_VAR_cf_api_token`
3. Runs `terraform` with forwarded arguments (plan, apply, destroy, etc.)
4. Auto-runs `terraform init` if `.terraform/` doesn't exist

Usage: `bash scripts/deploy.sh plan`
Usage: `bash scripts/deploy.sh apply -var="origin_ip=1.2.3.4"`

### scripts/import-cert.sh
Imports a Cloudflare Origin Certificate into macOS keychain:
1. Takes `<cert.pem>` and `<key.pem>` file paths as arguments
2. Combines into a PKCS12 bundle
3. Uses `security import` to add to login keychain

Usage: `bash scripts/import-cert.sh cert.pem key.pem`

### scripts/deploy-cert.sh
Deploys origin cert to the nginx server:
1. Takes `--ssh-target user@host`, `<cert.pem>`, `<key.pem>` as arguments
2. Rsyncs cert+key to server (destination path configurable, default `/root/dl.boldman.net/`)
3. SSHs to server and runs `nginx -s reload`

Usage: `bash scripts/deploy-cert.sh --ssh-target user@host cert.pem key.pem`

## One-Time Setup Procedure

1. Import `boldman.net` domain to Cloudflare dashboard (manual)
2. Note the assigned nameservers from Cloudflare
3. Update domain registrar nameservers to Cloudflare's
4. Wait for DNS propagation
5. Run `bash scripts/deploy.sh apply -var="origin_ip=<SERVER_IP>"` to create zone + test record
6. Generate an Origin Certificate in Cloudflare dashboard (or API)
7. Download the cert PEM and key PEM
8. Run `scripts/import-cert.sh` to install cert in macOS keychain
9. Run `scripts/deploy-cert.sh` to deploy cert to origin server
10. Verify `https://test.boldman.net` resolves through Cloudflare

## Future Work

- Replace test A record with real `dl.boldman.net` record pointing to origin
- Add Cloudflare Page Rules or Cache Rules for `/share/assets/` caching
- Consider Cloudflare Rate Limiting rules for the relay endpoint
