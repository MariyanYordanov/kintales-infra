#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 5: Firewall Configuration (UFW)
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [05-firewall] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }
fail() { echo "  ❌ $1"; log "FAIL: $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 5: Firewall Configuration (UFW)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: Without a firewall, anyone on the internet can try to"
echo "     connect to ANY port on your server — PostgreSQL (5432),"
echo "     MinIO (9000), SSH (22), everything."
echo ""
echo "     We configure UFW to allow ONLY:"
echo "     • Cloudflare (ports 80/443) — for web traffic"
echo "     • Your admin IP (port 2222) — for SSH"
echo "     • Everything else: BLOCKED"
echo ""
echo "RISK WITHOUT THIS: Bots will find your PostgreSQL port"
echo "     within hours and start brute-forcing it. MinIO console"
echo "     will be exposed to the internet. SSH will get thousands"
echo "     of automated login attempts per day."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

# ─── Load .env ───────────────────────────────────────

if [ ! -f "$ENV_FILE" ]; then
  fail ".env file not found. Copy .env.example to .env and fill in values."
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

ADMIN_IP="${ADMIN_IP:-}"
SSH_PORT="${SSH_PORT:-2222}"

if [ -z "$ADMIN_IP" ]; then
  fail "ADMIN_IP not set in .env. Set your static IP for SSH access."
fi

log "Starting firewall configuration (admin IP: $ADMIN_IP, SSH port: $SSH_PORT)"

# ─── SAFETY: Allow SSH FIRST ────────────────────────

echo "Step 1: Allow SSH from admin IP first (safety measure)..."
echo ""
echo "WHY: We ALWAYS set up SSH access before enabling the firewall."
echo "     If we enable the firewall first and block SSH by accident,"
echo "     we'd be permanently locked out of the server."

ufw allow from "$ADMIN_IP" to any port "$SSH_PORT" proto tcp comment "Admin SSH"
ok "SSH allowed from $ADMIN_IP on port $SSH_PORT"

# ─── Set defaults ────────────────────────────────────

echo ""
echo "Step 2: Set default policies..."
echo ""
echo "Default deny incoming = block everything unless explicitly allowed"
echo "Default allow outgoing = server can reach internet (for updates, DNS)"

ufw default deny incoming
ufw default allow outgoing
ok "Defaults: deny incoming, allow outgoing"

# ─── Fetch Cloudflare IPs ───────────────────────────

echo ""
echo "Step 3: Fetch current Cloudflare IP ranges..."
echo ""
echo "WHY: We only allow web traffic from Cloudflare's servers."
echo "     Direct access to our IP is blocked. This means:"
echo "     • Cloudflare DDoS protection is always active"
echo "     • Our real IP is hidden from attackers"
echo "     • All traffic goes through Cloudflare's WAF"

CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6)

CF_COUNT=0

echo "  Adding Cloudflare IPv4 ranges..."
while IFS= read -r ip; do
  if [ -n "$ip" ]; then
    ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare" 2>/dev/null || true
    CF_COUNT=$((CF_COUNT + 1))
  fi
done <<< "$CF_IPV4"

echo "  Adding Cloudflare IPv6 ranges..."
while IFS= read -r ip; do
  if [ -n "$ip" ]; then
    ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare" 2>/dev/null || true
    CF_COUNT=$((CF_COUNT + 1))
  fi
done <<< "$CF_IPV6"

ok "$CF_COUNT Cloudflare IP ranges added"

# ─── Allow localhost ─────────────────────────────────

echo ""
echo "Step 4: Allow localhost traffic..."
ufw allow from 127.0.0.1 comment "Localhost"
ok "Localhost allowed"

# ─── Enable UFW ──────────────────────────────────────

echo ""
echo "Step 5: Enable firewall..."
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ⚠️  Before enabling, verify SSH access is allowed!"
echo ""
echo "  Rule should show: $ADMIN_IP → port $SSH_PORT ALLOW"
echo ""
ufw status | grep "$SSH_PORT" || echo "  WARNING: SSH rule not found!"
echo ""
echo "═══════════════════════════════════════════════════════"
echo ""
read -p "Enable firewall now? (y/N): " ENABLE
if [ "$ENABLE" != "y" ] && [ "$ENABLE" != "Y" ]; then
  echo "Firewall NOT enabled. Run 'ufw enable' manually when ready."
  exit 0
fi

echo "y" | ufw enable
ok "UFW firewall enabled"

# ─── Set up weekly Cloudflare IP update ──────────────

echo ""
echo "Step 6: Schedule weekly Cloudflare IP update..."
echo ""
echo "WHY: Cloudflare occasionally adds new IP ranges. Without"
echo "     updating, traffic from new Cloudflare servers would be"
echo "     blocked, causing random connection failures."

# Create cron job for weekly update
CRON_LINE="0 3 * * 0 ${SCRIPT_DIR}/ssl/cloudflare-ips-update.sh >> /var/log/kintales-cloudflare-ips.log 2>&1"
(crontab -l 2>/dev/null | grep -v "cloudflare-ips-update" || true; echo "$CRON_LINE") | crontab -
ok "Weekly Cloudflare IP update scheduled (Sunday 3:00 AM)"

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 5 Complete — Firewall Active"
echo "═══════════════════════════════════════════════════════"
echo ""
ufw status verbose
echo ""
echo "  Summary:"
echo "    SSH:        allowed from $ADMIN_IP on port $SSH_PORT"
echo "    HTTP/HTTPS: allowed from $CF_COUNT Cloudflare IP ranges"
echo "    All other:  BLOCKED"
echo ""
echo "  ⚠️  TEST NOW (in a new terminal):"
echo "    ssh -p $SSH_PORT admin@[SERVER_IP]"
echo ""
echo "  Next step: sudo bash setup/06-fail2ban.sh"
echo ""

log "Step 5 completed successfully"
