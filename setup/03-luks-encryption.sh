#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 3: LUKS Full-Disk Encryption (GUIDE)
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [03-luks] $1" | tee -a "$LOGFILE"; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 3: LUKS Full-Disk Encryption"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: LUKS encrypts the entire disk contents. If someone"
echo "     steals an SSD, they cannot read any data without the"
echo "     encryption key. This protects against: discarded SSDs,"
echo "     SSDs sold on eBay, SSDs removed from the laptop."
echo ""
echo "RISK WITHOUT THIS: Anyone with physical access to an SSD"
echo "     can read ALL data — database, user photos, passwords"
echo "     — by plugging it into another computer."
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ⚠️  THIS IS A MANUAL PROCESS"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  LUKS encryption cannot be fully automated because:"
echo "  1. It reformats partitions (DESTROYS ALL DATA)"
echo "  2. It requires a reboot to verify auto-unlock"
echo "  3. If misconfigured, the system won't boot"
echo ""
echo "  Follow the step-by-step guide at:"
echo "    docs/LUKS-GUIDE.md"
echo ""
echo "  Our approach: AUTO-UNLOCK with key file in initramfs"
echo "  (server boots automatically without manual passphrase)"
echo ""

# ─── Show current disk state ────────────────────────

echo "Current disk layout:"
echo ""
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo ""

# ─── Check if LUKS already configured ───────────────

LUKS_FOUND=false
for dev in /dev/sda2 /dev/sdb2 /dev/nvme0n1p2 /dev/nvme1n1p2; do
  if [ -b "$dev" ] && cryptsetup isLuks "$dev" 2>/dev/null; then
    echo "  ✅ LUKS detected on $dev"
    LUKS_FOUND=true
  fi
done

if [ "$LUKS_FOUND" = true ]; then
  echo ""
  echo "  LUKS is already configured on some partitions."
  echo "  If this is from the Ubuntu installer, proceed to"
  echo "  verify auto-unlock is configured."
  echo ""
fi

# ─── Check if LUKS containers are open ──────────────

if [ -b "/dev/mapper/crypt-sda" ] || [ -b "/dev/mapper/crypt-sdb" ]; then
  echo "  ✅ LUKS containers are open:"
  ls /dev/mapper/crypt-* 2>/dev/null || true
  echo ""
  echo "  LUKS setup appears complete."
  echo "  Proceed to Step 4 (RAID setup)."
  echo ""
  log "LUKS already configured and open — skipping"
  exit 0
fi

# ─── Interactive guide ───────────────────────────────

echo "═══════════════════════════════════════════════════════"
echo "  Quick Reference (see docs/LUKS-GUIDE.md for details)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  1. Identify your disks:"
echo "     lsblk -d -o NAME,SIZE,MODEL"
echo ""
echo "  2. Partition each SSD (if needed):"
echo "     sudo parted /dev/sdX -- mklabel gpt"
echo "     sudo parted /dev/sdX -- mkpart boot ext4 1MiB 1GiB"
echo "     sudo parted /dev/sdX -- mkpart data 1GiB 100%"
echo ""
echo "  3. Encrypt each data partition:"
echo "     sudo cryptsetup luksFormat --type luks2 /dev/sdX2"
echo "     (Enter a STRONG passphrase — this is your recovery key)"
echo ""
echo "  4. Generate auto-unlock key file:"
echo "     sudo dd if=/dev/urandom of=/root/.luks-key bs=4096 count=1"
echo "     sudo chmod 400 /root/.luks-key"
echo "     sudo cryptsetup luksAddKey /dev/sda2 /root/.luks-key"
echo "     sudo cryptsetup luksAddKey /dev/sdb2 /root/.luks-key"
echo ""
echo "  5. Configure /etc/crypttab:"
echo "     crypt-sda  /dev/sda2  /root/.luks-key  luks,discard"
echo "     crypt-sdb  /dev/sdb2  /root/.luks-key  luks,discard"
echo ""
echo "  6. Update initramfs:"
echo "     echo 'KEYFILE_PATTERN=\"/root/.luks-key\"' | sudo tee /etc/cryptsetup-initramfs/conf-hook"
echo "     sudo update-initramfs -u -k all"
echo ""
echo "  7. Reboot and verify:"
echo "     sudo reboot"
echo "     ls /dev/mapper/crypt-sda /dev/mapper/crypt-sdb"
echo ""
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  After LUKS is working:"
echo "    sudo bash setup/04-raid-setup.sh"
echo ""

log "LUKS guide displayed — manual steps required"
