#!/usr/bin/env bash
set -euo pipefail

# Send test email and verify DKIM/SPF/DMARC

RECIPIENT="${1:-}"

if [ -z "$RECIPIENT" ]; then
  echo "Usage: bash postfix/test-email.sh your@email.com"
  exit 1
fi

echo ""
echo "Sending test email to: $RECIPIENT"
echo ""

# Find Postfix container
POSTFIX_CONTAINER=$(docker ps --format '{{.Names}}' | grep postfix | head -1)

if [ -z "$POSTFIX_CONTAINER" ]; then
  echo "❌ Postfix container not running"
  exit 1
fi

# Send test email
docker exec "$POSTFIX_CONTAINER" bash -c \
  "echo 'This is a test email from KinTales server ($(hostname)).

Sent at: $(date)
Purpose: Verify email delivery, DKIM, SPF, and DMARC

If you receive this email:
1. Check it arrived in INBOX (not spam)
2. View email headers — look for:
   - dkim=pass
   - spf=pass
   - dmarc=pass
3. Gmail: click \"Show original\" to see full headers

If this email is in SPAM, check:
- SPF record: dig TXT kintales.net
- DKIM record: dig TXT mail._domainkey.kintales.net
- IP reputation: https://www.barracudacentral.org/lookups
' | mail -s 'KinTales Test Email — $(date +%Y-%m-%d)' -r 'noreply@kintales.net' '$RECIPIENT'"

echo "✅ Test email sent to $RECIPIENT"
echo ""
echo "Check:"
echo "  1. Email arrived in inbox (not spam)"
echo "  2. Headers show dkim=pass, spf=pass"
echo "  3. For detailed score: https://www.mail-tester.com/"
