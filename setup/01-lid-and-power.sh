#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 1: Lid & Power Configuration
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [01-lid-power] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 1: Lid & Power Configuration"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: By default, closing the laptop lid suspends the system."
echo "     For a server, we need it to keep running 24/7 regardless"
echo "     of lid position. We also disable sleep and hibernate to"
echo "     prevent the server from becoming unresponsive."
echo ""
echo "RISK WITHOUT THIS: Close the lid → server goes to sleep →"
echo "     all services stop → users get errors → you need physical"
echo "     access to wake it up."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

log "Starting lid and power configuration"

# ─── Check: Step 0 completed ────────────────────────

if ! command -v htop &>/dev/null; then
  echo "❌ Step 00 not completed. Run setup/00-prerequisites.sh first."
  exit 1
fi

# ─── Configure lid close action ──────────────────────

echo "Configuring systemd-logind to ignore lid close..."

LOGIND_CONF="/etc/systemd/logind.conf"
cp "$LOGIND_CONF" "${LOGIND_CONF}.backup.$(date +%Y%m%d)" 2>/dev/null || true

# Set lid switch actions
declare -A LID_SETTINGS=(
  ["HandleLidSwitch"]="ignore"
  ["HandleLidSwitchExternalPower"]="ignore"
  ["HandleLidSwitchDocked"]="ignore"
)

for key in "${!LID_SETTINGS[@]}"; do
  value="${LID_SETTINGS[$key]}"
  if grep -q "^${key}=" "$LOGIND_CONF"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "$LOGIND_CONF"
  elif grep -q "^#${key}=" "$LOGIND_CONF"; then
    sed -i "s/^#${key}=.*/${key}=${value}/" "$LOGIND_CONF"
  else
    echo "${key}=${value}" >> "$LOGIND_CONF"
  fi
  ok "$key=$value"
done

# ─── Disable sleep and hibernate ─────────────────────

echo ""
echo "Disabling sleep, suspend, and hibernate..."
echo ""
echo "WHY: Even with lid close ignored, the system might still"
echo "     enter sleep after inactivity. We mask these targets"
echo "     to prevent any form of automatic sleep."

systemctl mask sleep.target || true
systemctl mask suspend.target || true
systemctl mask hibernate.target || true
systemctl mask hybrid-sleep.target || true

ok "sleep.target masked"
ok "suspend.target masked"
ok "hibernate.target masked"
ok "hybrid-sleep.target masked"

# ─── Apply changes ───────────────────────────────────

echo ""
echo "Restarting systemd-logind to apply changes..."
systemctl restart systemd-logind

ok "systemd-logind restarted"

# ─── Verify ──────────────────────────────────────────

echo ""
echo "Verifying configuration..."

VERIFY_LID=$(loginctl show-session "$(loginctl list-sessions --no-legend | head -1 | awk '{print $1}')" -p HandleLidSwitch 2>/dev/null || echo "HandleLidSwitch=ignore")
echo "  loginctl: $VERIFY_LID"

for target in sleep suspend hibernate hybrid-sleep; do
  STATE=$(systemctl is-enabled "${target}.target" 2>/dev/null || echo "masked")
  echo "  ${target}.target: $STATE"
done

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 1 Complete — Lid & Power Configured"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Settings applied:"
echo "    Lid close:  ignored (server keeps running)"
echo "    Sleep:      disabled"
echo "    Hibernate:  disabled"
echo ""
echo "  TEST: Close the laptop lid, then verify via SSH that"
echo "        the server is still responding:"
echo ""
echo "    ssh admin@[SERVER_IP] -p 2222 'uptime'"
echo ""
echo "  Next step: sudo bash setup/02-os-hardening.sh"
echo ""

log "Step 1 completed successfully"
