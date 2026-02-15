# LUKS Full-Disk Encryption Guide

## Overview

LUKS (Linux Unified Key Setup) encrypts the entire disk at rest. Even if someone steals the SSD, they cannot read the data without the encryption key.

**Our approach**: Auto-unlock using a key file stored in initramfs. The server boots automatically without manual passphrase entry.

**Trade-off**: If the entire laptop is stolen (with SSDs inside), the attacker has the key file too. LUKS primarily protects against: discarded SSDs, SSD sold separately, or SSD removed and read on another machine.

## Prerequisites

- Fresh Ubuntu Server 24.04 LTS install
- 2x SSDs detected (`lsblk` shows both)
- Step 00-prerequisites.sh completed
- **BACKUP any existing data** — encryption reformats the disk

## Important Warning

This process is **destructive** — all data on the encrypted partition will be lost. Perform this on a fresh install BEFORE storing any production data.

## Step-by-Step Guide

### Step 1: Identify Disks

```bash
lsblk -d -o NAME,SIZE,MODEL
# Example output:
# sda  512G  Samsung SSD 970 EVO Plus
# sdb  512G  Samsung SSD 970 EVO Plus
```

**Note**: Your device names may differ. Replace `/dev/sda` and `/dev/sdb` with your actual devices throughout this guide.

### Step 2: Partition Disks (if not already)

Each SSD needs:
- Partition 1: 1GB — `/boot` (unencrypted, needed for GRUB)
- Partition 2: Remaining — LUKS encrypted → RAID member

```bash
# SSD 1
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart boot ext4 1MiB 1GiB
sudo parted /dev/sda -- mkpart data 1GiB 100%
sudo parted /dev/sda -- set 1 boot on

# SSD 2 (identical layout)
sudo parted /dev/sdb -- mklabel gpt
sudo parted /dev/sdb -- mkpart boot ext4 1MiB 1GiB
sudo parted /dev/sdb -- mkpart data 1GiB 100%
```

### Step 3: Create LUKS Containers

```bash
# Encrypt SSD 1, partition 2
sudo cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 \
  --key-size 512 --hash sha256 /dev/sda2

# You'll be asked for a passphrase — use a STRONG one
# This passphrase is the recovery key. STORE IT SECURELY.

# Encrypt SSD 2, partition 2
sudo cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 \
  --key-size 512 --hash sha256 /dev/sdb2
```

### Step 4: Generate Auto-Unlock Key File

```bash
# Generate random key file
sudo dd if=/dev/urandom of=/root/.luks-key bs=4096 count=1
sudo chmod 400 /root/.luks-key

# Add key file to both LUKS containers
sudo cryptsetup luksAddKey /dev/sda2 /root/.luks-key
sudo cryptsetup luksAddKey /dev/sdb2 /root/.luks-key
```

Now both disks can be unlocked with either:
- The passphrase (for recovery/emergency)
- The key file (for automatic boot)

### Step 5: Open LUKS Containers

```bash
sudo cryptsetup open /dev/sda2 crypt-sda --key-file /root/.luks-key
sudo cryptsetup open /dev/sdb2 crypt-sdb --key-file /root/.luks-key

# Verify:
ls /dev/mapper/crypt-sda /dev/mapper/crypt-sdb
```

### Step 6: Configure Auto-Unlock

Edit `/etc/crypttab`:
```
crypt-sda  /dev/sda2  /root/.luks-key  luks,discard
crypt-sdb  /dev/sdb2  /root/.luks-key  luks,discard
```

Include key file in initramfs:
```bash
# Edit /etc/cryptsetup-initramfs/conf-hook
# Set: KEYFILE_PATTERN="/root/.luks-key"

echo 'KEYFILE_PATTERN="/root/.luks-key"' | sudo tee /etc/cryptsetup-initramfs/conf-hook

# Update initramfs
sudo update-initramfs -u -k all
```

### Step 7: Test (CRITICAL)

**Before rebooting**, verify the configuration:

```bash
# Check crypttab is correct
cat /etc/crypttab

# Check initramfs contains the key
lsinitramfs /boot/initrd.img-$(uname -r) | grep luks-key
# Should show: root/.luks-key

# Now reboot
sudo reboot
```

After reboot:
```bash
# Verify LUKS containers opened automatically
ls /dev/mapper/crypt-sda /dev/mapper/crypt-sdb

# Check LUKS status
sudo cryptsetup status crypt-sda
sudo cryptsetup status crypt-sdb
```

## After LUKS: Proceed to RAID

Once both LUKS containers auto-unlock on boot, proceed to [RAID-GUIDE.md](RAID-GUIDE.md) to create RAID 1 on top of `/dev/mapper/crypt-sda` and `/dev/mapper/crypt-sdb`.

## Recovery Procedures

### Forgot Key File Location
The key file is at `/root/.luks-key`. If the root filesystem is corrupted, you'll need the passphrase you set in Step 3.

### Key File Corrupted
Use the passphrase to unlock manually, then regenerate the key file:
```bash
sudo cryptsetup open /dev/sda2 crypt-sda  # Enter passphrase
sudo dd if=/dev/urandom of=/root/.luks-key bs=4096 count=1
sudo chmod 400 /root/.luks-key
sudo cryptsetup luksAddKey /dev/sda2 /root/.luks-key
sudo update-initramfs -u -k all
```

### SSD Replacement
If one SSD fails and is replaced:
1. Partition new SSD identically (Step 2)
2. Create LUKS on new partition (Step 3)
3. Add key file to new LUKS (Step 4)
4. Rebuild RAID (see [RAID-GUIDE.md](RAID-GUIDE.md))
