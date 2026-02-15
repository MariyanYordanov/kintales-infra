#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  Daily Backup — PostgreSQL + MinIO → GPG → USB
# ═══════════════════════════════════════════════════════
# Runs daily at 3:00 AM via cron
# See: backup/backup-cron.conf

LOGFILE="/var/log/kintales-backup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] $1" | tee -a "$LOGFILE"; }

# ─── Load config ─────────────────────────────────────

if [ ! -f "$ENV_FILE" ]; then
  log "ERROR: .env not found"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

BACKUP_DIR="/data/backups"
USB_MOUNT="${BACKUP_USB_MOUNT:-/mnt/backup-usb}"
PASSPHRASE_FILE="/root/.backup-passphrase"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DAY_OF_MONTH=$(date +%d)
BACKUP_PATH="${BACKUP_DIR}/daily/${TIMESTAMP}"

log "Starting daily backup: $TIMESTAMP"

# ─── Verify prerequisites ───────────────────────────

if [ ! -f "$PASSPHRASE_FILE" ]; then
  log "ERROR: GPG passphrase file not found at $PASSPHRASE_FILE"
  log "Create it: echo 'your-strong-passphrase' > $PASSPHRASE_FILE && chmod 400 $PASSPHRASE_FILE"
  exit 1
fi

mkdir -p "$BACKUP_PATH"

# ─── PostgreSQL dump ─────────────────────────────────

log "Dumping PostgreSQL database..."

docker exec kintales-server-postgres-1 \
  pg_dump -U kintales_backup -d kintales --format=custom \
  > "${BACKUP_PATH}/kintales_db.dump"

DB_SIZE=$(du -sh "${BACKUP_PATH}/kintales_db.dump" | awk '{print $1}')
log "PostgreSQL dump complete: $DB_SIZE"

# ─── Encrypt database dump ──────────────────────────

log "Encrypting database dump with GPG (AES-256)..."

gpg --symmetric --cipher-algo AES256 --batch \
  --passphrase-file "$PASSPHRASE_FILE" \
  "${BACKUP_PATH}/kintales_db.dump"

rm "${BACKUP_PATH}/kintales_db.dump"
log "Database dump encrypted: ${BACKUP_PATH}/kintales_db.dump.gpg"

# ─── MinIO data sync ────────────────────────────────

log "Syncing MinIO data..."

MINIO_DATA="/data/docker/volumes/kintales-server_minio_data/_data"
if [ -d "$MINIO_DATA" ]; then
  rsync -a --delete "$MINIO_DATA/" "${BACKUP_PATH}/minio/"
  MINIO_SIZE=$(du -sh "${BACKUP_PATH}/minio/" | awk '{print $1}')
  log "MinIO sync complete: $MINIO_SIZE"
else
  log "WARNING: MinIO data directory not found at $MINIO_DATA"
fi

# ─── Monthly backup (1st of month) ──────────────────

if [ "$DAY_OF_MONTH" = "01" ]; then
  MONTHLY_DIR="${BACKUP_DIR}/monthly/${TIMESTAMP}"
  log "Creating monthly backup copy..."
  cp -r "$BACKUP_PATH" "$MONTHLY_DIR"
  log "Monthly backup saved to $MONTHLY_DIR"
fi

# ─── Sync to USB drive ──────────────────────────────

if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
  log "Syncing to USB drive at $USB_MOUNT..."

  USB_BACKUP_DIR="${USB_MOUNT}/kintales"
  mkdir -p "${USB_BACKUP_DIR}/daily" "${USB_BACKUP_DIR}/monthly"

  rsync -a "${BACKUP_PATH}/" "${USB_BACKUP_DIR}/daily/${TIMESTAMP}/"

  if [ "$DAY_OF_MONTH" = "01" ]; then
    rsync -a "${BACKUP_PATH}/" "${USB_BACKUP_DIR}/monthly/${TIMESTAMP}/"
  fi

  log "USB sync complete"
else
  log "WARNING: USB drive not mounted at $USB_MOUNT — local backup only"
fi

# ─── Cleanup old backups ────────────────────────────

log "Cleaning up old backups..."

# Keep 30 days of daily backups
find "${BACKUP_DIR}/daily/" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

# Keep 12 months of monthly backups
find "${BACKUP_DIR}/monthly/" -maxdepth 1 -type d -mtime +365 -exec rm -rf {} \; 2>/dev/null || true

# Clean USB too
if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
  find "${USB_MOUNT}/kintales/daily/" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true
  find "${USB_MOUNT}/kintales/monthly/" -maxdepth 1 -type d -mtime +365 -exec rm -rf {} \; 2>/dev/null || true
fi

log "Cleanup complete"

# ─── Write success marker for Prometheus ─────────────

echo "backup_last_success $(date +%s)" > /var/lib/node_exporter/backup_last_success.prom 2>/dev/null || true

# ─── Telegram notification ──────────────────────────

TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | awk '{print $1}')

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  USB_STATUS="not mounted"
  if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
    USB_STATUS="synced"
  fi

  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=💾 Backup complete: ${TIMESTAMP}
Size: ${TOTAL_SIZE}
DB: ${DB_SIZE}
USB: ${USB_STATUS}" \
    > /dev/null 2>&1
fi

log "Daily backup completed successfully: $TOTAL_SIZE total"
