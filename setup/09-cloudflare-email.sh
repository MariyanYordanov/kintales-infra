#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 9: Cloudflare Email Routing
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [09-email] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 9: Cloudflare Email Routing"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: We need email for: password resets, user notifications,"
echo "     and admin alerts. Instead of running our own email server"
echo "     from day 1 (which is complex and risky with a new IP),"
echo "     we use Cloudflare Email Routing."
echo ""
echo "     Cloudflare handles INCOMING mail (forwarding to your"
echo "     personal email). The kintales-server Postfix container"
echo "     handles OUTGOING mail (password resets, notifications)."
echo ""
echo "WHY NOT SELF-HOSTED POSTFIX YET?"
echo "     New IP addresses often have poor email reputation."
echo "     Emails from unknown IPs frequently land in spam."
echo "     We'll migrate to self-hosted Postfix after 3-6 months"
echo "     when the IP has built reputation."
echo ""
echo "     See: postfix/ directory for future migration configs"
echo "     See: docs/EMAIL-GUIDE.md for full details"
echo ""

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

DOMAIN="${DOMAIN:-kintales.net}"

# ─── Instructions ────────────────────────────────────

echo "═══════════════════════════════════════════════════════"
echo "  MANUAL SETUP IN CLOUDFLARE DASHBOARD"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  1. Open: https://dash.cloudflare.com"
echo "  2. Select: $DOMAIN"
echo "  3. Go to: Email → Email Routing"
echo "  4. Click: Enable Email Routing"
echo "  5. Follow the wizard:"
echo ""
echo "     a. Add destination email (your personal email)"
echo "     b. Verify the destination (check inbox for verification)"
echo "     c. Create routing rules:"
echo "        • admin@$DOMAIN   → your personal email"
echo "        • *@$DOMAIN       → your personal email (catch-all)"
echo ""
echo "  6. Cloudflare will auto-create DNS records:"
echo "     MX records + SPF TXT record"
echo ""
echo "  7. Update SPF to include your server's IP for outgoing mail:"
echo "     Change the TXT record to:"
echo "     v=spf1 ip4:${SERVER_STATIC_IP:-[YOUR_STATIC_IP]} include:_spf.mx.cloudflare.net ~all"
echo ""

# ─── Verification ────────────────────────────────────

echo "═══════════════════════════════════════════════════════"
echo "  VERIFICATION"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  After Cloudflare setup, verify:"
echo ""
echo "  1. Check MX records:"
echo "     dig MX $DOMAIN"
echo "     → Should show Cloudflare MX servers"
echo ""
echo "  2. Check SPF record:"
echo "     dig TXT $DOMAIN"
echo "     → Should include: v=spf1 ... ~all"
echo ""
echo "  3. Test incoming email:"
echo "     Send email to admin@$DOMAIN"
echo "     → Should arrive at your personal email"
echo ""
echo "  4. Test outgoing email (after kintales-server deploy):"
echo "     docker exec kintales-postfix bash -c \\"
echo "       'echo \"Test\" | mail -s \"Test from KinTales\" your@email.com'"
echo "     → Check inbox (may be in spam initially)"
echo ""

# ─── DNS check (automated) ──────────────────────────

echo "Checking current DNS records..."
echo ""

MX_RECORDS=$(dig +short MX "$DOMAIN" 2>/dev/null || echo "")
if [ -n "$MX_RECORDS" ]; then
  echo "  Current MX records:"
  echo "$MX_RECORDS" | sed 's/^/    /'
  if echo "$MX_RECORDS" | grep -qi "cloudflare"; then
    ok "Cloudflare MX records detected"
  else
    echo "  ⚠️  MX records don't point to Cloudflare yet."
    echo "     Complete the Cloudflare setup above."
  fi
else
  echo "  ⚠️  No MX records found for $DOMAIN."
  echo "     Complete the Cloudflare setup above."
fi

SPF_RECORD=$(dig +short TXT "$DOMAIN" 2>/dev/null | grep "spf" || echo "")
if [ -n "$SPF_RECORD" ]; then
  echo "  Current SPF: $SPF_RECORD"
  ok "SPF record exists"
else
  echo "  ⚠️  No SPF record found. Will be created by Cloudflare."
fi

# ─── Migration note ──────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  FUTURE: Migration to Self-Hosted Postfix"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  When to migrate (after 3-6 months):"
echo "  • Test emails consistently land in inbox (not spam)"
echo "  • mail-tester.com score is 9+/10"
echo "  • IP reputation is clean (barracudacentral.org)"
echo ""
echo "  Migration files are in: postfix/"
echo "  • main.cf.template     — Postfix config"
echo "  • opendkim/            — DKIM key generation"
echo "  • test-email.sh        — Email delivery test"
echo ""
echo "  See: docs/EMAIL-GUIDE.md for full migration guide"
echo ""
echo "  Next step: sudo bash setup/10-monitoring.sh"
echo ""

log "Step 9 completed — Cloudflare Email Routing guide displayed"
