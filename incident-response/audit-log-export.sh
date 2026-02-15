#!/usr/bin/env bash
set -euo pipefail

# Export all logs for forensic analysis

LOGFILE="/var/log/kintales-maintenance.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [audit-export] $1" | tee -a "$LOGFILE"; }

EXPORT_DIR="/root/audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EXPORT_DIR"

log "Exporting audit logs to $EXPORT_DIR"

echo "Exporting logs..."

# System logs
cp /var/log/auth.log "$EXPORT_DIR/auth.log" 2>/dev/null || true
cp /var/log/syslog "$EXPORT_DIR/syslog" 2>/dev/null || true
cp /var/log/fail2ban.log "$EXPORT_DIR/fail2ban.log" 2>/dev/null || true
cp /var/log/kintales-*.log "$EXPORT_DIR/" 2>/dev/null || true

# Docker container logs
for container in $(docker ps -a --format '{{.Names}}' 2>/dev/null); do
  docker logs --timestamps "$container" > "${EXPORT_DIR}/docker-${container}.log" 2>&1 || true
done

# pgAudit logs (if PostgreSQL is running)
PG_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep postgres | head -1 || true)
if [ -n "$PG_CONTAINER" ]; then
  docker exec "$PG_CONTAINER" psql -U postgres -c \
    "SELECT * FROM pg_catalog.pg_stat_activity;" \
    > "${EXPORT_DIR}/pg-connections.txt" 2>/dev/null || true
  echo "  ✅ PostgreSQL connections exported"
fi

# UFW logs
grep "UFW" /var/log/syslog > "${EXPORT_DIR}/ufw.log" 2>/dev/null || true

# Last logins
last -100 > "${EXPORT_DIR}/last-logins.txt" 2>/dev/null || true
lastb -100 > "${EXPORT_DIR}/failed-logins.txt" 2>/dev/null || true

# Create archive
ARCHIVE="${EXPORT_DIR}.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")"
rm -rf "$EXPORT_DIR"

echo ""
echo "✅ Logs exported to: $ARCHIVE"
echo "   Size: $(du -sh "$ARCHIVE" | awk '{print $1}')"
echo ""
echo "Transfer to your local machine for analysis:"
echo "  scp -P ${SSH_PORT:-2222} root@[SERVER_IP]:$ARCHIVE ."

log "Audit logs exported to $ARCHIVE"
