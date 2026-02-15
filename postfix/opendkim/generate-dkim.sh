#!/usr/bin/env bash
set -euo pipefail

# Generate DKIM keys for email authentication

DOMAIN="${1:-kintales.net}"
SELECTOR="mail"
KEY_DIR="$(dirname "$0")/keys"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DKIM Key Generation for $DOMAIN"
echo "═══════════════════════════════════════════════════════"
echo ""

mkdir -p "$KEY_DIR"

# Generate 2048-bit RSA key pair
opendkim-genkey -b 2048 -d "$DOMAIN" -D "$KEY_DIR" -s "$SELECTOR" -v

echo ""
echo "Keys generated:"
echo "  Private: ${KEY_DIR}/${SELECTOR}.private"
echo "  Public:  ${KEY_DIR}/${SELECTOR}.txt"
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DNS RECORDS TO ADD IN CLOUDFLARE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "1. DKIM (TXT record):"
echo "   Name:  ${SELECTOR}._domainkey.${DOMAIN}"
echo "   Value:"
cat "${KEY_DIR}/${SELECTOR}.txt" | sed 's/.*(\s*//' | sed 's/\s*).*//' | tr -d '"\n\t '
echo ""
echo ""
echo "2. SPF (TXT record):"
echo "   Name:  ${DOMAIN}"
echo "   Value: v=spf1 ip4:[YOUR_STATIC_IP] -all"
echo ""
echo "3. DMARC (TXT record):"
echo "   Name:  _dmarc.${DOMAIN}"
echo "   Value: v=DMARC1; p=reject; rua=mailto:admin@${DOMAIN}"
echo ""
echo "4. MX (MX record — replace Cloudflare routing):"
echo "   Name:  ${DOMAIN}"
echo "   Value: mail.${DOMAIN} (priority 10)"
echo ""
echo "5. A (A record for mail subdomain):"
echo "   Name:  mail.${DOMAIN}"
echo "   Value: [YOUR_STATIC_IP]"
echo ""
echo "See: postfix/opendkim/README.md for full details"
