#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 0: Prerequisites — Verify Hardware & Install Base
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [00-prerequisites] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }
fail() { echo "  ❌ $1"; log "FAIL: $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 0: Prerequisites — Verify Hardware & Install Base"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: Before setting up the server, we verify that the"
echo "     hardware matches expectations and install essential"
echo "     system tools that all other scripts depend on."
echo ""
echo "RISK WITHOUT THIS: Later scripts may fail silently or"
echo "     produce incorrect results if run on unsupported"
echo "     hardware or without required packages."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

log "Starting prerequisites check"

# ─── Check: Ubuntu 24.04 LTS ─────────────────────────

echo "Checking Ubuntu version..."
if grep -q "24.04" /etc/os-release 2>/dev/null; then
  UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
  ok "Ubuntu $UBUNTU_VERSION detected"
else
  fail "Ubuntu 24.04 LTS required. Found: $(cat /etc/os-release | grep PRETTY_NAME)"
fi

# ─── Check: RAM ──────────────────────────────────────

echo "Checking RAM..."
TOTAL_RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
if [ "$TOTAL_RAM_GB" -ge 32 ]; then
  ok "RAM: ${TOTAL_RAM_GB}GB detected (minimum 32GB)"
else
  echo "  ⚠️  RAM: ${TOTAL_RAM_GB}GB detected (expected 64GB, minimum 32GB)"
  echo "     The server will work but with reduced performance."
  read -p "     Continue anyway? (y/N): " CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    fail "Aborted by user — insufficient RAM"
  fi
fi

# ─── Check: Disks (expect 2+ SSDs) ──────────────────

echo "Checking disks..."
DISK_COUNT=$(lsblk -d -n -o TYPE | grep -c "disk" || true)
echo "  Found $DISK_COUNT disk(s):"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk | while read -r line; do
  echo "    $line"
done

if [ "$DISK_COUNT" -ge 2 ]; then
  ok "2+ disks detected (ready for RAID 1)"
else
  echo "  ⚠️  Only $DISK_COUNT disk(s) found. RAID 1 requires 2 disks."
  echo "     You can continue without RAID, but there will be no"
  echo "     hardware redundancy."
  read -p "     Continue without RAID capability? (y/N): " CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    fail "Aborted by user — need 2 disks for RAID 1"
  fi
fi

# ─── Check: Network (Ethernet preferred) ────────────

echo "Checking network..."
ETH_INTERFACES=$(ip -o link show | grep -cE "enp|eno|eth" || true)
WIFI_INTERFACES=$(ip -o link show | grep -cE "wlp|wlan" || true)

if [ "$ETH_INTERFACES" -gt 0 ]; then
  ETH_NAME=$(ip -o link show | grep -oE "(enp|eno|eth)[a-z0-9]+" | head -1)
  ETH_STATE=$(ip -o link show "$ETH_NAME" | grep -oP "state \K\w+")
  if [ "$ETH_STATE" = "UP" ]; then
    ok "Ethernet $ETH_NAME is UP"
  else
    echo "  ⚠️  Ethernet $ETH_NAME detected but state is $ETH_STATE"
    echo "     Connect an Ethernet cable for reliable server operation."
  fi
else
  echo "  ⚠️  No Ethernet interface detected."
  echo "     WiFi is unreliable for servers. Use Ethernet if possible."
fi

# ─── Check: Internet connectivity ────────────────────

echo "Checking internet connectivity..."
if ping -c 2 -W 5 1.1.1.1 &>/dev/null; then
  ok "Internet connected (Cloudflare DNS reachable)"
else
  fail "No internet connectivity. Check network connection."
fi

# ─── Install base packages ───────────────────────────

echo ""
echo "Installing base packages..."
echo ""
echo "These packages provide essential system administration tools:"
echo "  curl, wget     — download files from internet"
echo "  gnupg          — encryption and key management"
echo "  git            — version control (to clone repos)"
echo "  htop           — interactive process monitor"
echo "  iotop          — disk I/O monitor"
echo "  smartmontools  — SSD/HDD health monitoring (SMART)"
echo "  net-tools      — network diagnostics (ifconfig, netstat)"
echo "  mdadm          — RAID array management"
echo "  ufw            — firewall management"
echo "  fail2ban       — brute force protection"
echo "  unattended-upgrades — automatic security patches"
echo "  lsb-release    — system identification"
echo "  software-properties-common — apt repository management"
echo ""

apt-get update
apt-get install -y \
  curl \
  wget \
  gnupg \
  git \
  htop \
  iotop \
  smartmontools \
  net-tools \
  mdadm \
  ufw \
  fail2ban \
  unattended-upgrades \
  lsb-release \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  jq

ok "Base packages installed"

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 0 Complete — Prerequisites Verified"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Hardware:"
echo "    Ubuntu:   $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
echo "    RAM:      ${TOTAL_RAM_GB}GB"
echo "    Disks:    $DISK_COUNT detected"
echo "    Network:  $(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\w+' || echo 'unknown')"
echo ""
echo "  Next step: sudo bash setup/01-lid-and-power.sh"
echo ""

log "Step 0 completed successfully"
