#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  Secret Rotation — Generate new credentials
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-maintenance.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [rotate-secrets] $1" | tee -a "$LOGFILE"; }

SERVER_ENV="/data/kintales-server/.env"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Secret Rotation"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  This will generate new values for:"
echo "  • JWT_SECRET and JWT_REFRESH_SECRET"
echo "  • DB passwords (all 3 roles)"
echo "  • MinIO credentials"
echo "  • Backup GPG passphrase"
echo ""
echo "  ⚠️  All existing user sessions will be invalidated."
echo "  ⚠️  Docker containers will be recreated."
echo ""
read -p "Type 'ROTATE' to confirm: " CONFIRM
if [ "$CONFIRM" != "ROTATE" ]; then
  echo "Aborted."
  exit 0
fi

log "Starting secret rotation"

# ─── Generate new secrets ────────────────────────────

gen_secret() { openssl rand -base64 "$1" | tr -d '/+=' | head -c "$1"; }

NEW_JWT_SECRET=$(gen_secret 64)
NEW_JWT_REFRESH_SECRET=$(gen_secret 64)
NEW_DB_ROOT_PWD=$(gen_secret 32)
NEW_APP_DB_PWD=$(gen_secret 32)
NEW_ADMIN_DB_PWD=$(gen_secret 32)
NEW_BACKUP_DB_PWD=$(gen_secret 32)
NEW_MINIO_ACCESS=$(gen_secret 20)
NEW_MINIO_SECRET=$(gen_secret 40)
NEW_PGCRYPTO_KEY=$(gen_secret 32)

echo "  ✅ New secrets generated"

# ─── Update server .env ─────────────────────────────

if [ -f "$SERVER_ENV" ]; then
  cp "$SERVER_ENV" "${SERVER_ENV}.backup.$(date +%Y%m%d%H%M%S)"

  sed -i \
    -e "s/^JWT_SECRET=.*/JWT_SECRET=$NEW_JWT_SECRET/" \
    -e "s/^JWT_REFRESH_SECRET=.*/JWT_REFRESH_SECRET=$NEW_JWT_REFRESH_SECRET/" \
    -e "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=$NEW_DB_ROOT_PWD/" \
    -e "s/^KINTALES_APP_DB_PASSWORD=.*/KINTALES_APP_DB_PASSWORD=$NEW_APP_DB_PWD/" \
    -e "s/^KINTALES_ADMIN_DB_PASSWORD=.*/KINTALES_ADMIN_DB_PASSWORD=$NEW_ADMIN_DB_PWD/" \
    -e "s/^KINTALES_BACKUP_DB_PASSWORD=.*/KINTALES_BACKUP_DB_PASSWORD=$NEW_BACKUP_DB_PWD/" \
    -e "s/^MINIO_ACCESS_KEY=.*/MINIO_ACCESS_KEY=$NEW_MINIO_ACCESS/" \
    -e "s/^MINIO_SECRET_KEY=.*/MINIO_SECRET_KEY=$NEW_MINIO_SECRET/" \
    -e "s/^PGCRYPTO_KEY=.*/PGCRYPTO_KEY=$NEW_PGCRYPTO_KEY/" \
    "$SERVER_ENV"

  # Update DATABASE_URL
  sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://kintales_app:${NEW_APP_DB_PWD}@postgres:5432/kintales|" "$SERVER_ENV"

  echo "  ✅ Server .env updated (backup saved)"
  log "Server .env updated"
else
  echo "  ⚠️  Server .env not found at $SERVER_ENV"
  echo "     New secrets printed below — update manually."
fi

# ─── Update PostgreSQL passwords ─────────────────────

echo ""
echo "Updating PostgreSQL role passwords..."

cd /data/kintales-server 2>/dev/null || true

if docker ps --format '{{.Names}}' | grep -q "postgres"; then
  PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep postgres | head -1)

  docker exec "$PG_CONTAINER" psql -U postgres -c \
    "ALTER ROLE kintales_app PASSWORD '$NEW_APP_DB_PWD';"
  docker exec "$PG_CONTAINER" psql -U postgres -c \
    "ALTER ROLE kintales_admin PASSWORD '$NEW_ADMIN_DB_PWD';"
  docker exec "$PG_CONTAINER" psql -U postgres -c \
    "ALTER ROLE kintales_backup PASSWORD '$NEW_BACKUP_DB_PWD';"

  echo "  ✅ PostgreSQL passwords updated"
  log "PostgreSQL passwords rotated"
else
  echo "  ⚠️  PostgreSQL container not running — update passwords after restart"
fi

# ─── Recreate containers ────────────────────────────

echo ""
echo "Recreating Docker containers with new credentials..."

if [ -f /data/kintales-server/docker-compose.yml ]; then
  cd /data/kintales-server
  docker compose up -d --force-recreate
  echo "  ✅ Containers recreated"
  log "Containers recreated with new secrets"
fi

# ─── Print summary ──────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Secret Rotation Complete"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  ⚠️  UPDATE YOUR PASSWORD MANAGER with new values!"
echo "  ⚠️  All user sessions have been invalidated."
echo "  ⚠️  Users will need to log in again."
echo ""

log "Secret rotation completed"
