#!/bin/bash
# Build + deploy web instant-share SPA and relay to boldman.net.
# Usage: SSH_USER=… SSH_HOST=boldman.net bash scripts/deploy.sh
set -euo pipefail
this_file="${BASH_SOURCE[0]}"
this_dir="$(cd "$(dirname "$this_file")" && pwd)"

cd "$this_dir/.."

ssh_target=$1

: "${WEB_ROOT:=/var/www/html/instant-share}"
: "${RELAY_ROOT:=/opt/instant-share-relay}"

bash scripts/build.sh

rsync -avz --delete dist/  "${ssh_target}:${WEB_ROOT}/"
rsync -avz relay/           "${ssh_target}:${RELAY_ROOT}/"

scp "${this_dir}/../deploy/instant-share-relay.service" "${ssh_target}:"
ssh "${ssh_target}" "sudo mv instant-share-relay.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl restart instant-share-relay.service"

echo "Deploy complete:"
