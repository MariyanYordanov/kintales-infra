#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  Monthly Backup Test — Verify backup integrity
# ═══════════════════════════════════════════════════════
# Runs monthly on the 1st at 4:00 AM via cron
# Does NOT affect production data

LOGFILE="/var/log/kintales-backup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [test-restore] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

BACKUP_DIR="/data/backups"
PASSPHRASE_FILE="/root/.backup-passphrase"
TEST_DB="kintales_test_restore"

log "Starting monthly backup test"

# ─── Find latest backup ─────────────────────────────

LATEST=$(ls -1t "${BACKUP_DIR}/daily/" 2>/dev/null | head -1)
if [ -z "$LATEST" ]; then
  log "ERROR: No backups found"
  exit 1
fi

BACKUP_PATH="${BACKUP_DIR}/daily/${LATEST}"
log "Testing backup: $LATEST"

# ─── Verify passphrase file ─────────────────────────

if [ ! -f "$PASSPHRASE_FILE" ]; then
  log "ERROR: Passphrase file not found"
  exit 1
fi

# ─── Decrypt backup ─────────────────────────────────

log "Decrypting database dump..."
gpg --decrypt --batch \
  --passphrase-file "$PASSPHRASE_FILE" \
  "${BACKUP_PATH}/kintales_db.dump.gpg" \
  > /tmp/kintales_test_restore.dump

log "Decryption successful"

# ─── Create test database ───────────────────────────

log "Creating temporary test database..."
docker exec kintales-server-postgres-1 \
  psql -U kintales_admin -c "DROP DATABASE IF EXISTS ${TEST_DB};" 2>/dev/null || true

docker exec kintales-server-postgres-1 \
  psql -U kintales_admin -c "CREATE DATABASE ${TEST_DB};"

# ─── Restore to test database ───────────────────────

log "Restoring to test database..."
docker exec -i kintales-server-postgres-1 \
  pg_restore -U kintales_admin -d "$TEST_DB" --no-owner \
  < /tmp/kintales_test_restore.dump

log "Restore to test database complete"

# ─── Verify integrity ───────────────────────────────

log "Verifying backup integrity..."

RESULT="PASS"
DETAILS=""

# Check table count
TABLE_COUNT=$(docker exec kintales-server-postgres-1 \
  psql -U kintales_admin -d "$TEST_DB" -t -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" \
  | tr -d ' ')

if [ "$TABLE_COUNT" -ge 15 ]; then
  DETAILS="${DETAILS}\n  ✅ Tables: $TABLE_COUNT"
  log "Tables: $TABLE_COUNT (OK)"
else
  DETAILS="${DETAILS}\n  ❌ Tables: $TABLE_COUNT (expected >= 15)"
  RESULT="FAIL"
  log "Tables: $TABLE_COUNT (FAIL)"
fi

# Check profiles table has data
PROFILE_COUNT=$(docker exec kintales-server-postgres-1 \
  psql -U kintales_admin -d "$TEST_DB" -t -c \
  "SELECT count(*) FROM profiles;" 2>/dev/null \
  | tr -d ' ' || echo "0")

DETAILS="${DETAILS}\n  📊 Profiles: $PROFILE_COUNT"
log "Profiles: $PROFILE_COUNT"

# Check family trees
TREE_COUNT=$(docker exec kintales-server-postgres-1 \
  psql -U kintales_admin -d "$TEST_DB" -t -c \
  "SELECT count(*) FROM family_trees;" 2>/dev/null \
  | tr -d ' ' || echo "0")

DETAILS="${DETAILS}\n  📊 Family trees: $TREE_COUNT"
log "Family trees: $TREE_COUNT"

# ─── Cleanup ────────────────────────────────────────

log "Cleaning up test database..."
docker exec kintales-server-postgres-1 \
  psql -U kintales_admin -c "DROP DATABASE IF EXISTS ${TEST_DB};"

rm -f /tmp/kintales_test_restore.dump

log "Cleanup complete"

# ─── Report ──────────────────────────────────────────

log "Backup test result: $RESULT"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Backup Test Results"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Backup tested: $LATEST"
echo "  Result: $RESULT"
echo -e "$DETAILS"
echo ""

# ─── Telegram notification ──────────────────────────

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  EMOJI="✅"
  if [ "$RESULT" = "FAIL" ]; then EMOJI="❌"; fi

  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${EMOJI} Monthly backup test: ${RESULT}
Backup: ${LATEST}
Tables: ${TABLE_COUNT}
Profiles: ${PROFILE_COUNT}
Trees: ${TREE_COUNT}" \
    > /dev/null 2>&1
fi

log "Monthly backup test completed: $RESULT"
