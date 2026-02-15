#!/usr/bin/env bash
set -euo pipefail

# SSL certificate expiry check
LOGFILE="/var/log/kintales-maintenance.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cert-check] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

DOMAIN="${DOMAIN:-kintales.net}"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

log "Checking SSL certificate for $DOMAIN"

if [ ! -f "$CERT_PATH" ]; then
  log "ERROR: Certificate not found at $CERT_PATH"
  exit 1
fi

EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

log "Certificate expires: $EXPIRY ($DAYS_LEFT days remaining)"

if [ "$DAYS_LEFT" -lt 7 ]; then
  log "CRITICAL: Certificate expires in $DAYS_LEFT days!"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=🔴 CRITICAL: SSL certificate for $DOMAIN expires in $DAYS_LEFT days! Run: certbot renew --force-renewal" \
      > /dev/null 2>&1
  fi
elif [ "$DAYS_LEFT" -lt 14 ]; then
  log "WARNING: Certificate expires in $DAYS_LEFT days"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=🟡 SSL certificate for $DOMAIN expires in $DAYS_LEFT days. Auto-renewal should handle this." \
      > /dev/null 2>&1
  fi
else
  log "Certificate OK: $DAYS_LEFT days remaining"
fi

echo "SSL certificate for $DOMAIN: expires in $DAYS_LEFT days ($EXPIRY)"
