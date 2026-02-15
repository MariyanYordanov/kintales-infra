#!/usr/bin/env bash
set -euo pipefail

# Notify all users about a data breach (GDPR requirement)

LOGFILE="/var/log/kintales-maintenance.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [notify-users] $1" | tee -a "$LOGFILE"; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  User Breach Notification"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  GDPR requires notifying affected users within 72 hours"
echo "  of discovering a personal data breach."
echo ""
echo "  This script will:"
echo "  1. Query all user emails from the database"
echo "  2. Send a breach notification email to each user"
echo ""

read -p "Type 'NOTIFY' to confirm: " CONFIRM
if [ "$CONFIRM" != "NOTIFY" ]; then
  echo "Aborted."
  exit 0
fi

log "Starting user breach notification"

# Get user emails
PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep postgres | head -1)
if [ -z "$PG_CONTAINER" ]; then
  echo "❌ PostgreSQL container not running. Start it first."
  exit 1
fi

EMAILS=$(docker exec "$PG_CONTAINER" psql -U kintales_admin -d kintales -t -c \
  "SELECT email FROM profiles WHERE email IS NOT NULL;" 2>/dev/null | tr -d ' ')

EMAIL_COUNT=$(echo "$EMAILS" | grep -c "@" || echo "0")

echo ""
echo "  Found $EMAIL_COUNT user email addresses."
echo ""

if [ "$EMAIL_COUNT" -eq 0 ]; then
  echo "  No emails found. Nothing to send."
  exit 0
fi

echo "  Preview of notification (sent via kintales-server Postfix):"
echo ""
echo "  Subject: Important Security Notice — KinTales"
echo "  Body: We are writing to inform you of a security"
echo "        incident that may have affected your account..."
echo ""
read -p "Send notifications to $EMAIL_COUNT users? (y/N): " SEND
if [ "$SEND" != "y" ] && [ "$SEND" != "Y" ]; then
  echo "Aborted. Emails NOT sent."
  exit 0
fi

# Send via Postfix container
POSTFIX_CONTAINER=$(docker ps --format '{{.Names}}' | grep postfix | head -1)
SENT=0
FAILED=0

while IFS= read -r email; do
  if [ -n "$email" ] && echo "$email" | grep -q "@"; then
    if docker exec "$POSTFIX_CONTAINER" bash -c "echo 'We are writing to inform you of a security incident that may have affected your KinTales account. We discovered unauthorized access to our system. We have taken immediate steps to secure our systems, including rotating all credentials and patching the vulnerability. As a precaution, we recommend changing your password. If you have questions, contact us at admin@kintales.net.' | mail -s 'Important Security Notice — KinTales' -r 'noreply@kintales.net' '$email'" 2>/dev/null; then
      SENT=$((SENT + 1))
    else
      FAILED=$((FAILED + 1))
      log "Failed to send to: $email"
    fi
  fi
done <<< "$EMAILS"

echo ""
echo "  ✅ Sent: $SENT"
echo "  ❌ Failed: $FAILED"
echo ""

log "Breach notification: $SENT sent, $FAILED failed"
