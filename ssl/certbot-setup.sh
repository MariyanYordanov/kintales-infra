#!/usr/bin/env bash
set -euo pipefail

# Certbot initial setup helper
# Called by setup/08-ssl-domain.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ .env file not found. Copy .env.example to .env."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

DOMAIN="${DOMAIN:-kintales.net}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "❌ CLOUDFLARE_API_TOKEN not set in .env"
  exit 1
fi

# Install certbot
apt-get install -y certbot python3-certbot-dns-cloudflare

# Configure credentials
mkdir -p /root/.secrets
cat > /root/.secrets/cloudflare.ini << EOF
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
chmod 600 /root/.secrets/cloudflare.ini

# Request certificate
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

echo "✅ Certificate obtained for $DOMAIN and *.$DOMAIN"
certbot certificates
