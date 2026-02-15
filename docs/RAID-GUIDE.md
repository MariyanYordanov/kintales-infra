# RAID 1 Setup Guide

## Overview

RAID 1 (mirroring) writes identical data to both SSDs simultaneously. If one SSD fails, the other continues operating with zero downtime. You replace the failed SSD and rebuild the array.

**RAID 1 does NOT replace backups.** RAID protects against hardware failure; backups protect against data corruption, accidental deletion, ransomware, and software bugs.

## Prerequisites

- LUKS encryption completed (see [LUKS-GUIDE.md](LUKS-GUIDE.md))
- Both LUKS containers open: `/dev/mapper/crypt-sda` and `/dev/mapper/crypt-sdb`
- `mdadm` installed (`apt install mdadm`)

## Creating the RAID 1 Array

### Step 1: Create Array

```bash
sudo mdadm --create /dev/md0 \
  --level=1 \
  --raid-devices=2 \
  /dev/mapper/crypt-sda \
  /dev/mapper/crypt-sdb
```

The initial sync takes time (depends on SSD size). Monitor with:
```bash
watch cat /proc/mdstat
# Wait until [UU] appears (both disks active)
```

### Step 2: Format and Mount

```bash
# Format as ext4
sudo mkfs.ext4 -L kintales-data /dev/md0

# Create mount point
sudo mkdir -p /data

# Mount
sudo mount /dev/md0 /data

# Add to fstab for auto-mount on boot
echo '/dev/md0  /data  ext4  defaults  0  2' | sudo tee -a /etc/fstab
```

### Step 3: Save RAID Configuration

```bash
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u
```

### Step 4: Verify

```bash
# Check RAID status
cat /proc/mdstat
# Should show: md0 : active raid1 ... [2/2] [UU]

# Check mount
df -h /data
# Should show /dev/md0 mounted on /data

# Check detail
sudo mdadm --detail /dev/md0
```

## Directory Structure on /data

After RAID setup, create the data directories:

```bash
sudo mkdir -p /data/{docker,backups,monitoring}
sudo chown root:docker /data/docker
```

- `/data/docker` — Docker data-root (all containers, volumes, images)
- `/data/backups` — Local backup storage
- `/data/monitoring` — Prometheus/Grafana data

## Recovery: Single Disk Failure

### Symptoms
```bash
cat /proc/mdstat
# Shows: md0 : active raid1 ... [2/1] [U_]  ← one disk missing
```

Prometheus/Grafana will also alert via Telegram.

### Steps

1. **Identify failed disk**:
```bash
sudo mdadm --detail /dev/md0
# Look for "State : removed" or "faulty"
```

2. **Remove failed disk from array**:
```bash
sudo mdadm /dev/md0 --remove /dev/mapper/crypt-sdX  # the failed one
```

3. **Replace physical SSD** (power off if needed)

4. **Partition new SSD** (same layout as original — see [LUKS-GUIDE.md](LUKS-GUIDE.md) Step 2)

5. **Encrypt new SSD** (LUKS — see [LUKS-GUIDE.md](LUKS-GUIDE.md) Steps 3-4)

6. **Add to array**:
```bash
sudo mdadm /dev/md0 --add /dev/mapper/crypt-sdX  # the new one
```

7. **Monitor rebuild**:
```bash
watch cat /proc/mdstat
# Wait for [UU] — rebuild complete
```

Rebuild time depends on SSD size (typically 30-60 minutes for 512GB).

## Health Monitoring

### Manual Check
```bash
cat /proc/mdstat
sudo mdadm --detail /dev/md0
```

### Automated Check
The `maintenance/disk-health-check.sh` script checks RAID health and sends Telegram alerts.

### SMART Monitoring
```bash
# Check SSD health
sudo smartctl -a /dev/sda
sudo smartctl -a /dev/sdb

# Key indicators:
# - Reallocated_Sector_Ct: should be 0
# - Wear_Leveling_Count: SSD wear (lower = more worn)
# - Media_Wearout_Indicator: 100 = new, 0 = end of life
```

## Important Notes

- **Never run RAID on raw SSDs** — always on LUKS containers (encryption layer underneath)
- **Both SSDs should be identical** (same model, same capacity) for optimal RAID 1
- **RAID is not backup** — if you accidentally delete a file, it's deleted from both disks instantly
- **Test recovery procedure** before going to production (replace SSD in test environment first)
