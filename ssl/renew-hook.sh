#!/usr/bin/env bash
set -euo pipefail

# Post-renewal hook — called by certbot after successful renewal
# Reloads Nginx to pick up new certificate

LOGFILE="/var/log/kintales-certbot.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [renew-hook] $1" >> "$LOGFILE"; }

log "Certificate renewed — reloading services"

# Reload Nginx (kintales-server)
if docker ps --format '{{.Names}}' | grep -q "nginx"; then
  NGINX_CONTAINER=$(docker ps --format '{{.Names}}' | grep nginx | head -1)
  docker exec "$NGINX_CONTAINER" nginx -s reload
  log "Nginx reloaded ($NGINX_CONTAINER)"
  echo "✅ Nginx reloaded"
else
  log "WARNING: Nginx container not found"
  echo "⚠️  Nginx container not found — manual reload needed"
fi

# Send Telegram notification
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"

  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=🔒 SSL certificate renewed successfully on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S')" \
      > /dev/null 2>&1
    log "Telegram notification sent"
  fi
fi

log "Renewal hook completed"
