# Backup Guide

## Strategy: USB Drive Rotation

Two USB drives, swapped weekly. One always connected (receiving backups), one always off-site (protection against fire/theft/flood).

### Equipment Needed

- 2x USB 3.0 external drives, minimum 500GB each
- Label: **"KINTALES BACKUP A"** and **"KINTALES BACKUP B"**
- Store off-site drive in a secure location (home, safe deposit box, trusted friend)

### Rotation Schedule

| Week | Drive A | Drive B |
|------|---------|---------|
| 1 | Connected → receiving daily backups | Off-site (secure location) |
| 2 | Off-site (secure location) | Connected → receiving daily backups |
| 3 | Connected → receiving daily backups | Off-site (secure location) |
| ... | Alternating weekly | Alternating weekly |

**Swap day**: Every Monday (set a calendar reminder!)

### Swap Procedure

```bash
# 1. Safely unmount current drive
sudo umount /mnt/backup-usb

# 2. Physically disconnect drive A, connect drive B

# 3. Mount new drive
sudo mount /dev/sdc1 /mnt/backup-usb

# 4. Verify mount
df -h /mnt/backup-usb

# 5. Check last backup date on new drive
ls -la /mnt/backup-usb/kintales/daily/ | tail -5
```

## What Gets Backed Up

### Daily (3:00 AM, automated via cron)

| Component | Method | Size Estimate |
|-----------|--------|--------------|
| PostgreSQL | `pg_dump` → GPG encrypted | ~50-200 MB |
| MinIO (photos, audio, avatars) | `rsync` | Grows with usage |
| Docker volumes metadata | `docker volume ls` | Minimal |

### Not Backed Up (recreatable)

- Docker images (can be re-pulled)
- Node modules (can be re-installed)
- Logs older than 30 days (rotated)
- ClamAV virus definitions (auto-updated)

## Retention Policy

| Type | Retention | Location |
|------|-----------|----------|
| Daily backups | 30 days | `/data/backups/daily/` + USB |
| Monthly backups (1st of month) | 12 months | `/data/backups/monthly/` + USB |

## Backup Structure on USB

```
/mnt/backup-usb/kintales/
├── daily/
│   ├── 20240115_030000/
│   │   ├── kintales_db.sql.gpg    # Encrypted DB dump
│   │   └── minio/                  # MinIO data copy
│   ├── 20240116_030000/
│   └── ...
└── monthly/
    ├── 20240101_030000/
    └── ...
```

## Encryption

All database backups are encrypted with GPG (AES-256):

```bash
# Encrypt
gpg --symmetric --cipher-algo AES256 --batch \
  --passphrase-file /root/.backup-passphrase \
  kintales_db.sql

# Decrypt
gpg --decrypt --batch \
  --passphrase-file /root/.backup-passphrase \
  kintales_db.sql.gpg > kintales_db.sql
```

**The passphrase is stored in**:
1. `/root/.backup-passphrase` on the server
2. Your password manager (REQUIRED — this is your last resort)
3. Printed copy in a sealed envelope in your safe (recommended)

**If you lose the passphrase, all encrypted backups are UNRECOVERABLE.**

## Restore Procedures

### Full Restore (disaster recovery)

```bash
sudo bash backup/restore.sh
# Interactive: select backup date, confirm, restore
```

### Restore Single Table

```bash
# Decrypt backup
gpg --decrypt --batch --passphrase-file /root/.backup-passphrase \
  /mnt/backup-usb/kintales/daily/YYYYMMDD_HHMMSS/kintales_db.sql.gpg \
  > /tmp/kintales_full.sql

# Extract single table (example: stories)
grep -A 999999 'COPY public.stories' /tmp/kintales_full.sql | \
  head -n $(grep -c '' /tmp/stories_data.txt) > /tmp/stories_restore.sql

# Restore to database
docker exec -i kintales-postgres psql -U kintales_admin kintales < /tmp/stories_restore.sql

# Cleanup
rm /tmp/kintales_full.sql /tmp/stories_restore.sql
```

### Restore MinIO Data

```bash
# Rsync from backup to MinIO volume
sudo rsync -av /mnt/backup-usb/kintales/daily/YYYYMMDD_HHMMSS/minio/ \
  /data/docker/volumes/kintales_minio_data/_data/

# Restart MinIO container
docker restart kintales-minio
```

## Monthly Backup Test

Automated via `backup/test-restore.sh` (runs 1st of each month at 4:00 AM):

1. Decrypts latest backup
2. Creates temporary database
3. Restores into temp DB
4. Verifies table counts and sample queries
5. Drops temp DB
6. Sends Telegram notification with results

**Always verify test results!** A backup you haven't tested is a backup you don't have.

## Troubleshooting

### "No space left on USB drive"
```bash
# Check USB usage
du -sh /mnt/backup-usb/kintales/daily/
du -sh /mnt/backup-usb/kintales/monthly/

# Manual cleanup (remove backups older than 30 days)
find /mnt/backup-usb/kintales/daily/ -maxdepth 1 -mtime +30 -exec rm -rf {} \;
```

### "USB drive not detected"
```bash
# Check if device is recognized
lsblk
dmesg | tail -20  # Check kernel messages

# Try different USB port
# Check USB cable
```

### "GPG decryption failed"
- Verify passphrase file exists: `cat /root/.backup-passphrase`
- Try manual decryption: `gpg --decrypt --batch --passphrase "YOUR_PASSPHRASE" file.gpg`
- If passphrase lost: recover from password manager or printed copy
