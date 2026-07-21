#!/bin/bash
# Build + deploy web instant-share SPA and relay to boldman.net.
# Usage: SSH_USER=… SSH_HOST=boldman.net bash scripts/deploy.sh
set -euo pipefail
this_file="${BASH_SOURCE[0]}"
this_dir="$(cd "$(dirname "$this_file")" && pwd)"

cd "$this_dir/.."

while [ $# -gt 0 ]; do
    case "$1" in
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --ssh-host)
            SSH_HOST="$2"
            shift 2
            ;;
        --ssh-target)
            SSH_TARGET="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

ssh_target=
if [ -n "${SSH_TARGET:-}" ]; then
    ssh_target="$SSH_TARGET"
elif [ -n "${SSH_USER:-}" ] && [ -n "${SSH_HOST:-}" ]; then
    ssh_target="${SSH_USER}@${SSH_HOST}"
else
    echo "Usage: $0 --ssh-user <user> --ssh-host <host>"
    echo "   or: $0 --ssh-target <user@host>"
    exit 1
fi

: "${WEB_ROOT:=/var/www/html/instant-share}"
: "${RELAY_ROOT:=/opt/instant-share-relay}"

bash scripts/build.sh

rsync -avz --delete dist/  "${ssh_target}:${WEB_ROOT}/"
rsync -avz relay/           "${ssh_target}:${RELAY_ROOT}/"

scp "${this_dir}/../deploy/instant-share-relay.service" "${ssh_target}:"
ssh "${ssh_target}" "sudo mv instant-share-relay.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl restart instant-share-relay.service"

scp "${this_dir}/../../../dt_image_search/deploy/nginx/dl.boldman.conf" "${ssh_target}:"
ssh "${ssh_target}" "sudo mv dl.boldman.conf /etc/nginx/conf.d/ && sudo nginx -s reload"

echo "Deploy completed!"
