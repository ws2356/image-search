#!/bin/bash
# Build + deploy web instant-share SPA and relay to boldman.net.
# Usage: SSH_USER=… SSH_HOST=boldman.net bash scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SSH_USER:?set SSH_USER}"
: "${SSH_HOST:=boldman.net}"
: "${WEB_ROOT:=/var/www/html/instant-share}"
: "${RELAY_ROOT:=/opt/instant-share-relay}"

bash scripts/build.sh

rsync -avz --delete dist/  "${SSH_USER}@${SSH_HOST}:${WEB_ROOT}/"
rsync -avz relay/           "${SSH_USER}@${SSH_HOST}:${RELAY_ROOT}/"

ssh "${SSH_USER}@${SSH_HOST}" "systemctl restart instant-share-relay || (cd ${RELAY_ROOT} && npm i && SYSTEMD_UNIT=/etc/systemd/system/instant-share-relay.service; [ -f \$SYSTEMD_UNIT ] || cat > \$SYSTEMD_UNIT <<'UNIT'
[Unit]
Description=Instant-Share WebSocket Relay
After=network.target
[Service]
ExecStart=/usr/bin/node ${RELAY_ROOT}/relay.mjs
Restart=always
Environment=PORT=8787
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now instant-share-relay)"

echo "Deploy complete:"
echo "  SPA:  https://${SSH_HOST}/share"
echo "  Relay: wss://${SSH_HOST}/relay"
