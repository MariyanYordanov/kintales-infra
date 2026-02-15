#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  EMERGENCY SHUTDOWN
#  Stops all services, preserves logs, blocks all access
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-maintenance.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [EMERGENCY] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

ADMIN_IP="${ADMIN_IP:-}"
SSH_PORT="${SSH_PORT:-2222}"
INCIDENT_DIR="/root/incident-$(date +%Y%m%d-%H%M%S)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          ⚠️  EMERGENCY SHUTDOWN                      ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  This will:                                         ║"
echo "║  1. Stop ALL Docker containers                      ║"
echo "║  2. Block ALL ports except SSH from admin IP        ║"
echo "║  3. Preserve all logs for forensic analysis         ║"
echo "║                                                     ║"
echo "║  Services will be OFFLINE until manually restored.  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

read -p "Type 'EMERGENCY' to confirm: " CONFIRM
if [ "$CONFIRM" != "EMERGENCY" ]; then
  echo "Aborted."
  exit 0
fi

log "EMERGENCY SHUTDOWN INITIATED"

# ─── Preserve logs ───────────────────────────────────

echo "Preserving logs..."
mkdir -p "$INCIDENT_DIR"

cp /var/log/auth.log "$INCIDENT_DIR/" 2>/dev/null || true
cp /var/log/fail2ban.log "$INCIDENT_DIR/" 2>/dev/null || true
cp /var/log/kintales-*.log "$INCIDENT_DIR/" 2>/dev/null || true

# Docker logs
for container in $(docker ps -a --format '{{.Names}}'); do
  docker logs "$container" > "${INCIDENT_DIR}/${container}.log" 2>&1 || true
done

log "Logs preserved to $INCIDENT_DIR"

# ─── Stop all Docker containers ──────────────────────

echo "Stopping ALL Docker containers..."
docker stop $(docker ps -q) 2>/dev/null || true
log "All Docker containers stopped"

# ─── Lock down firewall ─────────────────────────────

echo "Resetting firewall — blocking everything except admin SSH..."
ufw --force reset
ufw default deny incoming
ufw default deny outgoing

if [ -n "$ADMIN_IP" ]; then
  ufw allow from "$ADMIN_IP" to any port "$SSH_PORT" proto tcp
  # Allow outgoing DNS and HTTPS (for emergency communication)
  ufw allow out 53
  ufw allow out 443
fi

echo "y" | ufw enable
log "Firewall locked down — only SSH from $ADMIN_IP allowed"

# ─── Telegram notification ──────────────────────────

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  curl -s --max-time 10 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=🚨 EMERGENCY SHUTDOWN on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S')
All services stopped. Firewall locked down.
Logs preserved at: $INCIDENT_DIR" \
    > /dev/null 2>&1 || true
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  EMERGENCY SHUTDOWN COMPLETE                        ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  All services: STOPPED                              ║"
echo "║  Firewall: SSH only from admin IP                   ║"
echo "║  Logs: $INCIDENT_DIR"
echo "║                                                     ║"
echo "║  Next steps:                                        ║"
echo "║  1. bash incident-response/audit-log-export.sh      ║"
echo "║  2. Analyze logs in $INCIDENT_DIR"
echo "║  3. Fix vulnerability                               ║"
echo "║  4. bash incident-response/rotate-secrets.sh        ║"
echo "║  5. Restore firewall: bash setup/05-firewall.sh     ║"
echo "║  6. Restart services                                ║"
echo "╚══════════════════════════════════════════════════════╝"

log "Emergency shutdown completed"
