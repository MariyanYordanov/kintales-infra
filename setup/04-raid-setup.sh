#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 4: RAID 1 Setup
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [04-raid] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }
fail() { echo "  ❌ $1"; log "FAIL: $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 4: RAID 1 Setup (Mirroring)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: RAID 1 writes identical data to both SSDs. If one"
echo "     SSD fails, the server keeps running on the other with"
echo "     zero downtime. You replace the failed SSD and the array"
echo "     rebuilds automatically."
echo ""
echo "RISK WITHOUT THIS: A single SSD failure = complete data loss"
echo "     and full service outage until you restore from backup."
echo "     SSDs have a limited lifespan (3-5 years under heavy use)."
echo ""
echo "NOTE: RAID is NOT backup! It protects against hardware failure,"
echo "     not against: accidental deletion, data corruption,"
echo "     ransomware, or software bugs."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

log "Starting RAID 1 setup"

# ─── Check: LUKS containers open ────────────────────

echo "Checking LUKS containers..."

RAID_DEV1=""
RAID_DEV2=""

if [ -b "/dev/mapper/crypt-sda" ] && [ -b "/dev/mapper/crypt-sdb" ]; then
  RAID_DEV1="/dev/mapper/crypt-sda"
  RAID_DEV2="/dev/mapper/crypt-sdb"
  ok "LUKS containers found: $RAID_DEV1 and $RAID_DEV2"
elif [ -b "/dev/sda2" ] && [ -b "/dev/sdb2" ]; then
  echo "  ⚠️  LUKS not detected. Using raw partitions."
  echo "     It's STRONGLY recommended to encrypt first (Step 3)."
  read -p "     Continue without encryption? (y/N): " CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    echo "  Run setup/03-luks-encryption.sh first."
    exit 0
  fi
  RAID_DEV1="/dev/sda2"
  RAID_DEV2="/dev/sdb2"
else
  fail "Cannot find 2 suitable partitions for RAID. Check disk setup."
fi

# ─── Check: RAID already exists ──────────────────────

if [ -b "/dev/md0" ]; then
  echo ""
  echo "  RAID array /dev/md0 already exists:"
  cat /proc/mdstat
  echo ""

  if mountpoint -q /data 2>/dev/null; then
    ok "/data is mounted on RAID array — skipping setup"
    echo ""
    echo "  RAID is already configured."
    echo "  Next step: sudo bash setup/05-firewall.sh"
    exit 0
  fi
fi

# ─── Create RAID 1 array ────────────────────────────

echo ""
echo "Creating RAID 1 array from:"
echo "  Device 1: $RAID_DEV1"
echo "  Device 2: $RAID_DEV2"
echo ""
echo "This will DESTROY any existing data on these devices."
echo ""
read -p "Type 'CREATE RAID' to continue: " CONFIRM
if [ "$CONFIRM" != "CREATE RAID" ]; then
  echo "Aborted."
  exit 0
fi

mdadm --create /dev/md0 \
  --level=1 \
  --raid-devices=2 \
  "$RAID_DEV1" \
  "$RAID_DEV2"

ok "RAID 1 array /dev/md0 created"

# ─── Wait for initial sync ──────────────────────────

echo ""
echo "RAID initial sync started. This may take 30-60 minutes."
echo "You can continue — the array is usable during sync."
echo ""
echo "Current status:"
cat /proc/mdstat
echo ""

# ─── Format as ext4 ─────────────────────────────────

echo "Formatting RAID array as ext4..."
mkfs.ext4 -L kintales-data /dev/md0
ok "Formatted as ext4 (label: kintales-data)"

# ─── Mount at /data ──────────────────────────────────

echo ""
echo "Mounting at /data..."
mkdir -p /data
mount /dev/md0 /data

# Add to fstab (if not already there)
if ! grep -q "/dev/md0" /etc/fstab; then
  echo "/dev/md0  /data  ext4  defaults  0  2" >> /etc/fstab
  ok "Added to /etc/fstab for auto-mount"
fi

ok "Mounted at /data ($(df -h /data | awk 'NR==2 {print $2}') total)"

# ─── Create data directories ────────────────────────

echo ""
echo "Creating data directories..."
mkdir -p /data/{docker,backups,monitoring}
ok "Created /data/docker, /data/backups, /data/monitoring"

# ─── Save RAID config ───────────────────────────────

echo ""
echo "Saving RAID configuration..."
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u
ok "RAID config saved to /etc/mdadm/mdadm.conf"

# ─── Configure RAID alerts ──────────────────────────

echo ""
echo "Configuring RAID degradation monitoring..."
echo ""
echo "WHY: If one SSD fails, RAID 1 continues on the remaining"
echo "     disk — but you MUST replace the failed disk ASAP."
echo "     Without alerting, you might not notice until the"
echo "     second disk also fails (then ALL data is lost)."

# mdadm has built-in monitoring via systemd
systemctl enable mdmonitor
systemctl start mdmonitor
ok "RAID monitoring enabled (mdmonitor service)"

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 4 Complete — RAID 1 Active"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Array:    /dev/md0 (RAID 1 mirror)"
echo "  Mount:    /data"
echo "  Size:     $(df -h /data | awk 'NR==2 {print $2}')"
echo "  Status:   $(cat /proc/mdstat | grep md0 | head -1)"
echo ""
echo "  Verify:   cat /proc/mdstat"
echo "            Should show [UU] (both disks active)"
echo ""
echo "  Next step: sudo bash setup/05-firewall.sh"
echo ""

log "Step 4 completed successfully"
