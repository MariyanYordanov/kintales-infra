#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 8: Domain & SSL Certificate (Let's Encrypt)
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [08-ssl] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }
fail() { echo "  ❌ $1"; log "FAIL: $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 8: Domain & SSL Certificate (Let's Encrypt)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: HTTPS (SSL/TLS) encrypts all traffic between users and"
echo "     our server. Without it, passwords, personal data, and"
echo "     family photos travel in plain text. Every modern browser"
echo "     warns users about non-HTTPS sites."
echo ""
echo "     We use Let's Encrypt — free, automated SSL certificates."
echo "     We get a WILDCARD certificate (*.kintales.net) so it"
echo "     covers all subdomains: api.kintales.net, monitoring, etc."
echo ""
echo "RISK WITHOUT THIS: Data exposed in transit, browsers show"
echo "     'Not Secure' warning, App Store/Play Store may reject"
echo "     apps that communicate over plain HTTP."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

# ─── Load .env ───────────────────────────────────────

if [ ! -f "$ENV_FILE" ]; then
  fail ".env file not found. Copy .env.example to .env and fill in values."
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
DOMAIN="${DOMAIN:-kintales.net}"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  fail "CLOUDFLARE_API_TOKEN not set in .env. Create at: https://dash.cloudflare.com/profile/api-tokens"
fi

log "Starting SSL setup for $DOMAIN"

# ─── Check: Docker installed ────────────────────────

if ! command -v docker &>/dev/null; then
  fail "Docker not installed. Run setup/07-docker.sh first."
fi

# ─── Check: existing certificates ────────────────────

if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "  Certificate already exists for $DOMAIN:"
  certbot certificates 2>/dev/null | grep -A 3 "Certificate Name" || true
  echo ""
  read -p "  Renew/replace? (y/N): " REPLACE
  if [ "$REPLACE" != "y" ] && [ "$REPLACE" != "Y" ]; then
    ok "Certificate already exists — skipping"
    echo ""
    echo "  Next step: sudo bash setup/09-cloudflare-email.sh"
    exit 0
  fi
fi

# ─── Install certbot ────────────────────────────────

echo "Installing certbot and Cloudflare DNS plugin..."
echo ""
echo "WHY: Certbot automates the Let's Encrypt certificate process."
echo "     The Cloudflare DNS plugin allows us to prove domain ownership"
echo "     by creating a DNS TXT record (DNS challenge). This is required"
echo "     for wildcard certificates and works even when the web server"
echo "     isn't running yet."

apt-get install -y certbot python3-certbot-dns-cloudflare
ok "Certbot installed"

# ─── Configure Cloudflare credentials ────────────────

echo ""
echo "Configuring Cloudflare API credentials..."

mkdir -p /root/.secrets
cat > /root/.secrets/cloudflare.ini << EOF
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
chmod 600 /root/.secrets/cloudflare.ini

ok "Cloudflare credentials saved (restricted permissions)"

# ─── Request wildcard certificate ────────────────────

echo ""
echo "Requesting wildcard certificate for $DOMAIN..."
echo ""
echo "This creates a DNS TXT record via Cloudflare API to prove"
echo "domain ownership. The record is temporary and auto-cleaned."
echo ""

certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  -d "$DOMAIN" \
  -d "*.$DOMAIN" \
  --non-interactive \
  --agree-tos \
  --email "admin@$DOMAIN" \
  --preferred-challenges dns-01

ok "Wildcard certificate obtained for $DOMAIN and *.$DOMAIN"

# ─── Set up auto-renewal ────────────────────────────

echo ""
echo "Configuring automatic certificate renewal..."
echo ""
echo "WHY: Let's Encrypt certificates expire after 90 days."
echo "     Auto-renewal runs twice daily (certbot checks if renewal"
echo "     is needed — it only renews when <30 days remain)."

# Create renewal hook
RENEW_HOOK="${SCRIPT_DIR}/ssl/renew-hook.sh"
if [ -f "$RENEW_HOOK" ]; then
  chmod +x "$RENEW_HOOK"
fi

# Add cron for renewal (certbot systemd timer may already exist)
CRON_LINE="0 0,12 * * * certbot renew --quiet --deploy-hook ${RENEW_HOOK} >> /var/log/kintales-certbot.log 2>&1"
(crontab -l 2>/dev/null | grep -v "certbot renew" || true; echo "$CRON_LINE") | crontab -

ok "Auto-renewal cron configured (twice daily)"

# ─── Verify ──────────────────────────────────────────

echo ""
echo "Verifying certificate..."
certbot certificates
echo ""

# Check expiry
EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" | cut -d= -f2)
ok "Certificate valid until: $EXPIRY"

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 8 Complete — SSL Certificate Active"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Domain:      $DOMAIN (+ *.$DOMAIN wildcard)"
echo "  Cert path:   /etc/letsencrypt/live/$DOMAIN/"
echo "  Expires:     $EXPIRY"
echo "  Auto-renew:  twice daily via cron"
echo ""
echo "  DNS records needed (if not already set in Cloudflare):"
echo "    A    $DOMAIN          → ${SERVER_STATIC_IP:-[YOUR_IP]}"
echo "    A    api.$DOMAIN      → ${SERVER_STATIC_IP:-[YOUR_IP]}"
echo "    A    monitoring.$DOMAIN → ${SERVER_STATIC_IP:-[YOUR_IP]}"
echo "    CNAME www.$DOMAIN     → $DOMAIN"
echo ""
echo "  Next step: sudo bash setup/09-cloudflare-email.sh"
echo ""

log "Step 8 completed successfully"
