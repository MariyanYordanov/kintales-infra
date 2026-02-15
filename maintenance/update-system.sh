#!/usr/bin/env bash
set -euo pipefail

# System update — apt + Docker images
LOGFILE="/var/log/kintales-maintenance.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [update] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

log "Starting system update"

echo "Updating system packages..."
apt-get update
apt-get upgrade -y
log "APT upgrade complete"

echo "Pulling latest Docker images..."
if [ -f /data/kintales-server/docker-compose.yml ]; then
  cd /data/kintales-server
  docker compose pull
  log "Docker images pulled for kintales-server"
fi

if [ -f /data/monitoring/docker-compose.monitoring.yml ]; then
  cd /data/monitoring
  docker compose -f docker-compose.monitoring.yml pull
  log "Docker images pulled for monitoring"
fi

echo "Cleaning unused Docker resources..."
docker system prune -f
log "Docker cleanup complete"

# Telegram notification
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=🔄 System update completed on $(hostname) at $(date '+%Y-%m-%d %H:%M')" \
    > /dev/null 2>&1
fi

log "System update completed"
echo "✅ System update complete"
