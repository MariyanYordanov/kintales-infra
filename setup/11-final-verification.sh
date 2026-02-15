#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 11: Final Verification
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [11-verify] $1" | tee -a "$LOGFILE"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

SSH_PORT="${SSH_PORT:-2222}"
DOMAIN="${DOMAIN:-kintales.net}"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 11: Final Verification"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Running all checks and generating status report..."
echo ""

PASS=0
FAIL=0
WARN=0

check_pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); log "PASS: $1"; }
check_fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); log "FAIL: $1"; }
check_warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); log "WARN: $1"; }

# ─── OS ──────────────────────────────────────────────

echo "── OS ─────────────────────────────────────────────"

if grep -q "24.04" /etc/os-release 2>/dev/null; then
  check_pass "Ubuntu $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
else
  check_fail "Ubuntu 24.04 LTS not detected"
fi

if [ "$(timedatectl show --value -p Timezone)" = "Europe/Sofia" ]; then
  check_pass "Timezone: Europe/Sofia"
else
  check_warn "Timezone: $(timedatectl show --value -p Timezone) (expected Europe/Sofia)"
fi

if timedatectl show --value -p NTPSynchronized | grep -q "yes"; then
  check_pass "NTP: synchronized"
else
  check_warn "NTP: not synchronized"
fi

if [ "$(hostname)" = "kintales-prod" ]; then
  check_pass "Hostname: kintales-prod"
else
  check_warn "Hostname: $(hostname) (expected kintales-prod)"
fi

# ─── Lid & Power ────────────────────────────────────

echo ""
echo "── Lid & Power ──────────────────────────────────────"

if systemctl is-enabled sleep.target 2>/dev/null | grep -q "masked"; then
  check_pass "Sleep: disabled (masked)"
else
  check_warn "Sleep: not masked"
fi

if grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf 2>/dev/null; then
  check_pass "Lid close: ignored"
else
  check_warn "Lid close: not configured"
fi

# ─── LUKS ────────────────────────────────────────────

echo ""
echo "── LUKS Encryption ──────────────────────────────────"

LUKS_COUNT=0
for dev in /dev/sda2 /dev/sdb2 /dev/nvme0n1p2 /dev/nvme1n1p2; do
  if [ -b "$dev" ] && cryptsetup isLuks "$dev" 2>/dev/null; then
    LUKS_COUNT=$((LUKS_COUNT + 1))
  fi
done

if [ "$LUKS_COUNT" -ge 2 ]; then
  check_pass "LUKS: $LUKS_COUNT encrypted partitions"
elif [ "$LUKS_COUNT" -eq 1 ]; then
  check_warn "LUKS: only $LUKS_COUNT partition encrypted (expected 2)"
else
  check_warn "LUKS: not detected (may be using different device names)"
fi

# ─── RAID ────────────────────────────────────────────

echo ""
echo "── RAID ─────────────────────────────────────────────"

if [ -b "/dev/md0" ]; then
  RAID_STATUS=$(cat /proc/mdstat | grep md0 | head -1)
  if echo "$RAID_STATUS" | grep -q "\[UU\]"; then
    check_pass "RAID 1: [UU] healthy"
  elif echo "$RAID_STATUS" | grep -q "\[U_\]\|\[_U\]"; then
    check_fail "RAID 1: DEGRADED — one disk missing!"
  else
    check_warn "RAID 1: status unclear — $RAID_STATUS"
  fi

  if mountpoint -q /data 2>/dev/null; then
    DISK_USAGE=$(df -h /data | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$DISK_USAGE" -lt 80 ]; then
      check_pass "/data mounted (${DISK_USAGE}% used)"
    else
      check_warn "/data mounted but ${DISK_USAGE}% full"
    fi
  else
    check_fail "/data not mounted"
  fi
else
  check_warn "RAID: /dev/md0 not found"
fi

# ─── Firewall ────────────────────────────────────────

echo ""
echo "── Firewall ─────────────────────────────────────────"

if ufw status | grep -q "Status: active"; then
  check_pass "UFW: active"

  CF_RULES=$(ufw status | grep -c "Cloudflare" 2>/dev/null || echo "0")
  if [ "$CF_RULES" -gt 0 ]; then
    check_pass "Cloudflare IPs: $CF_RULES rules"
  else
    check_warn "No Cloudflare IP rules found"
  fi

  if ufw status | grep -q "$SSH_PORT"; then
    check_pass "SSH port $SSH_PORT: allowed"
  else
    check_fail "SSH port $SSH_PORT: NOT in firewall rules!"
  fi
else
  check_fail "UFW: not active"
fi

# ─── Fail2ban ────────────────────────────────────────

echo ""
echo "── Fail2ban ─────────────────────────────────────────"

if systemctl is-active fail2ban &>/dev/null; then
  JAIL_COUNT=$(fail2ban-client status 2>/dev/null | grep "Number of jail" | awk '{print $NF}' || echo "0")
  check_pass "Fail2ban: active ($JAIL_COUNT jails)"
else
  check_fail "Fail2ban: not running"
fi

# ─── Docker ──────────────────────────────────────────

echo ""
echo "── Docker ───────────────────────────────────────────"

if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  check_pass "Docker: $DOCKER_VER"

  if docker compose version &>/dev/null; then
    COMPOSE_VER=$(docker compose version | awk '{print $NF}')
    check_pass "Compose: $COMPOSE_VER"
  else
    check_fail "Docker Compose: not installed"
  fi

  if grep -q "/data/docker" /etc/docker/daemon.json 2>/dev/null; then
    check_pass "Docker data-root: /data/docker"
  else
    check_warn "Docker data-root: not on RAID (/data)"
  fi
else
  check_fail "Docker: not installed"
fi

# ─── SSL ─────────────────────────────────────────────

echo ""
echo "── SSL Certificate ──────────────────────────────────"

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" | cut -d= -f2)
  EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

  if [ "$DAYS_LEFT" -gt 30 ]; then
    check_pass "SSL: valid, expires in $DAYS_LEFT days ($EXPIRY)"
  elif [ "$DAYS_LEFT" -gt 0 ]; then
    check_warn "SSL: expires in $DAYS_LEFT days — renew soon!"
  else
    check_fail "SSL: EXPIRED!"
  fi
else
  check_warn "SSL: certificate not found for $DOMAIN"
fi

# ─── SSH ─────────────────────────────────────────────

echo ""
echo "── SSH ──────────────────────────────────────────────"

if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
  check_pass "SSH: key-only (password auth disabled)"
else
  check_warn "SSH: password auth may be enabled"
fi

CURRENT_SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | grep -oP '\d+$' | head -1 || echo "unknown")
if [ "$CURRENT_SSH_PORT" = "$SSH_PORT" ]; then
  check_pass "SSH: port $SSH_PORT"
else
  check_warn "SSH: port $CURRENT_SSH_PORT (expected $SSH_PORT)"
fi

# ─── Monitoring ──────────────────────────────────────

echo ""
echo "── Monitoring ───────────────────────────────────────"

if curl -s -o /dev/null http://localhost:9090/-/ready 2>/dev/null; then
  check_pass "Prometheus: running"
else
  check_warn "Prometheus: not reachable"
fi

if curl -s -o /dev/null http://localhost:3001/api/health 2>/dev/null; then
  check_pass "Grafana: running"
else
  check_warn "Grafana: not reachable"
fi

if curl -s -o /dev/null http://localhost:9093/-/ready 2>/dev/null; then
  check_pass "Alertmanager: running"
else
  check_warn "Alertmanager: not reachable"
fi

# ─── Backup ──────────────────────────────────────────

echo ""
echo "── Backup ───────────────────────────────────────────"

if crontab -l 2>/dev/null | grep -q "daily-backup"; then
  check_pass "Backup cron: configured"
else
  check_warn "Backup cron: not found (run backup/backup-cron.conf)"
fi

if mountpoint -q "${BACKUP_USB_MOUNT:-/mnt/backup-usb}" 2>/dev/null; then
  check_pass "Backup USB: mounted at ${BACKUP_USB_MOUNT:-/mnt/backup-usb}"
else
  check_warn "Backup USB: not mounted"
fi

# ─── Report ──────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         KinTales Server Status Report               ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  ✅ Passed:  %-38s ║\n" "$PASS"
printf "║  ⚠️  Warnings: %-37s ║\n" "$WARN"
printf "║  ❌ Failed:  %-38s ║\n" "$FAIL"
echo "╠══════════════════════════════════════════════════════╣"

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "║  🎉 ALL CHECKS PASSED — Server is production-ready! ║"
elif [ "$FAIL" -eq 0 ]; then
  echo "║  ⚡ Server functional with $WARN warning(s)           ║"
else
  echo "║  🔧 $FAIL critical issue(s) need attention            ║"
fi

echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ─── Save report ─────────────────────────────────────

REPORT_FILE="/root/kintales-setup-report-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "KinTales Server Setup Report"
  echo "Generated: $(date)"
  echo "Hostname: $(hostname)"
  echo ""
  echo "Results: $PASS passed, $WARN warnings, $FAIL failed"
} > "$REPORT_FILE"

echo "  Report saved to: $REPORT_FILE"

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "  Server is ready for kintales-server deployment!"
  echo ""
  echo "  Deploy kintales-server:"
  echo "    cd /data"
  echo "    git clone https://github.com/MariyanYordanov/kintales-server.git"
  echo "    cd kintales-server"
  echo "    cp .env.example .env"
  echo "    nano .env  # Fill in production secrets"
  echo "    docker compose up -d"
  echo "    npm run db:migrate"
  echo ""
fi

log "Final verification: $PASS passed, $WARN warnings, $FAIL failed"
