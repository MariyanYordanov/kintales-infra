#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  Restore from Backup
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-backup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [restore] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

BACKUP_DIR="/data/backups"
USB_MOUNT="${BACKUP_USB_MOUNT:-/mnt/backup-usb}"
PASSPHRASE_FILE="/root/.backup-passphrase"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  KinTales — Restore from Backup"
echo "═══════════════════════════════════════════════════════"
echo ""

# ─── List available backups ──────────────────────────

echo "Available backups:"
echo ""
echo "  Local (/data/backups/daily/):"
if [ -d "${BACKUP_DIR}/daily" ]; then
  ls -1 "${BACKUP_DIR}/daily/" 2>/dev/null | tail -10 | while read -r d; do
    SIZE=$(du -sh "${BACKUP_DIR}/daily/$d" 2>/dev/null | awk '{print $1}')
    echo "    $d  ($SIZE)"
  done
else
  echo "    (none)"
fi

echo ""
echo "  USB ($USB_MOUNT/kintales/daily/):"
if mountpoint -q "$USB_MOUNT" 2>/dev/null && [ -d "${USB_MOUNT}/kintales/daily" ]; then
  ls -1 "${USB_MOUNT}/kintales/daily/" 2>/dev/null | tail -10 | while read -r d; do
    SIZE=$(du -sh "${USB_MOUNT}/kintales/daily/$d" 2>/dev/null | awk '{print $1}')
    echo "    $d  ($SIZE)"
  done
else
  echo "    (not mounted or empty)"
fi

echo ""
read -p "Enter backup timestamp to restore (e.g. 20240115_030000): " SELECTED

# ─── Find backup ────────────────────────────────────

RESTORE_PATH=""
if [ -d "${BACKUP_DIR}/daily/${SELECTED}" ]; then
  RESTORE_PATH="${BACKUP_DIR}/daily/${SELECTED}"
elif [ -d "${BACKUP_DIR}/monthly/${SELECTED}" ]; then
  RESTORE_PATH="${BACKUP_DIR}/monthly/${SELECTED}"
elif mountpoint -q "$USB_MOUNT" 2>/dev/null && [ -d "${USB_MOUNT}/kintales/daily/${SELECTED}" ]; then
  RESTORE_PATH="${USB_MOUNT}/kintales/daily/${SELECTED}"
else
  echo "❌ Backup not found: $SELECTED"
  exit 1
fi

echo ""
echo "Selected backup: $RESTORE_PATH"
echo "Contents:"
ls -la "$RESTORE_PATH/"
echo ""

# ─── Confirm ────────────────────────────────────────

echo "═══════════════════════════════════════════════════════"
echo "  ⚠️  WARNING: This will OVERWRITE the current database"
echo "     and MinIO data. This action is IRREVERSIBLE."
echo "═══════════════════════════════════════════════════════"
echo ""
read -p "Type 'RESTORE' to continue: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
  echo "Aborted."
  exit 0
fi

log "Starting restore from $RESTORE_PATH"

# ─── Stop kintales-server ───────────────────────────

echo ""
echo "Stopping kintales-server containers..."
cd /data/kintales-server 2>/dev/null || { echo "❌ kintales-server not found at /data/kintales-server"; exit 1; }
docker compose stop api

log "API container stopped"

# ─── Restore database ───────────────────────────────

if [ -f "${RESTORE_PATH}/kintales_db.dump.gpg" ]; then
  echo ""
  echo "Decrypting and restoring database..."

  gpg --decrypt --batch \
    --passphrase-file "$PASSPHRASE_FILE" \
    "${RESTORE_PATH}/kintales_db.dump.gpg" \
    > /tmp/kintales_restore.dump

  docker exec -i kintales-server-postgres-1 \
    pg_restore -U kintales_admin -d kintales --clean --if-exists \
    < /tmp/kintales_restore.dump

  rm /tmp/kintales_restore.dump
  log "Database restored successfully"
  echo "  ✅ Database restored"
else
  echo "  ⚠️  No database dump found in backup"
fi

# ─── Restore MinIO data ─────────────────────────────

if [ -d "${RESTORE_PATH}/minio" ]; then
  echo ""
  echo "Restoring MinIO data..."

  MINIO_DATA="/data/docker/volumes/kintales-server_minio_data/_data"
  rsync -a --delete "${RESTORE_PATH}/minio/" "$MINIO_DATA/"

  log "MinIO data restored"
  echo "  ✅ MinIO data restored"
else
  echo "  ⚠️  No MinIO data found in backup"
fi

# ─── Restart services ───────────────────────────────

echo ""
echo "Restarting kintales-server..."
docker compose up -d

log "Services restarted"

# ─── Verify ──────────────────────────────────────────

echo ""
echo "Waiting for services to start..."
sleep 10

echo "Verifying..."
if docker exec kintales-server-postgres-1 pg_isready -U postgres -d kintales &>/dev/null; then
  echo "  ✅ PostgreSQL is ready"
else
  echo "  ❌ PostgreSQL is not responding"
fi

HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "000")
if [ "$HEALTH" = "200" ]; then
  echo "  ✅ API is healthy"
else
  echo "  ⚠️  API returned HTTP $HEALTH"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Restore Complete"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Restored from: $SELECTED"
echo "  Verify the application is working correctly."
echo ""

log "Restore completed from $SELECTED"
