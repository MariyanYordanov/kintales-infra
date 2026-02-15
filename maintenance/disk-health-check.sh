#!/usr/bin/env bash
set -euo pipefail

# Disk health check — SMART + RAID + space
LOGFILE="/var/log/kintales-maintenance.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [disk-health] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

ALERTS=""

log "Starting disk health check"

# ─── RAID status ─────────────────────────────────────

if [ -b "/dev/md0" ]; then
  RAID_STATUS=$(cat /proc/mdstat 2>/dev/null || echo "")
  if echo "$RAID_STATUS" | grep -q "\[UU\]"; then
    log "RAID: [UU] healthy"
  else
    log "ALERT: RAID degraded!"
    ALERTS="${ALERTS}🔴 RAID DEGRADED — replace failed disk ASAP!\n"
  fi
else
  log "RAID: /dev/md0 not found"
fi

# ─── Disk space ──────────────────────────────────────

for MOUNT in "/" "/data"; do
  if mountpoint -q "$MOUNT" 2>/dev/null; then
    USAGE=$(df -h "$MOUNT" | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$USAGE" -ge 90 ]; then
      log "ALERT: $MOUNT is ${USAGE}% full (CRITICAL)"
      ALERTS="${ALERTS}🔴 Disk $MOUNT: ${USAGE}% full (CRITICAL)\n"
    elif [ "$USAGE" -ge 80 ]; then
      log "WARNING: $MOUNT is ${USAGE}% full"
      ALERTS="${ALERTS}🟡 Disk $MOUNT: ${USAGE}% full (WARNING)\n"
    else
      log "Disk $MOUNT: ${USAGE}% used (OK)"
    fi
  fi
done

# ─── SMART status ────────────────────────────────────

for DISK in /dev/sda /dev/sdb; do
  if [ -b "$DISK" ]; then
    SMART_STATUS=$(smartctl -H "$DISK" 2>/dev/null | grep -i "overall" || echo "unknown")
    if echo "$SMART_STATUS" | grep -qi "passed"; then
      log "SMART $DISK: PASSED"
    elif echo "$SMART_STATUS" | grep -qi "failed"; then
      log "ALERT: SMART $DISK: FAILED"
      ALERTS="${ALERTS}🔴 SMART $DISK: FAILED — disk may be dying!\n"
    else
      log "SMART $DISK: $SMART_STATUS"
    fi
  fi
done

# ─── Send alerts ────────────────────────────────────

if [ -n "$ALERTS" ] && [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=💿 Disk Health Alert on $(hostname):
${ALERTS}" \
    > /dev/null 2>&1
  log "Alert sent via Telegram"
fi

log "Disk health check completed"
