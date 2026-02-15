# Disaster Recovery

## Scenario 1: Single SSD Failure

**Impact**: Zero downtime (RAID 1 continues on remaining disk)
**Recovery time**: 1-2 hours (new SSD + RAID rebuild)

### Steps
1. **Identify failure**: `cat /proc/mdstat` shows `[U_]` instead of `[UU]`
2. **Order replacement SSD** (same model and size)
3. **Replace SSD**: Power off → swap → power on
4. **Rebuild RAID**: See [RAID-GUIDE.md](RAID-GUIDE.md) recovery section
5. **Verify**: Wait for rebuild, check `[UU]`

### Prevention
- Monitor SMART data monthly (`maintenance/disk-health-check.sh`)
- Replace SSDs proactively at 80% wear indicator

## Scenario 2: Both SSDs Fail Simultaneously

**Impact**: Full service outage
**Recovery time**: 4-8 hours (new hardware + restore from backup)

### Steps
1. **Get new SSDs** (or new hardware entirely)
2. **Fresh Ubuntu Server 24.04 install**
3. **Run setup scripts** (00-11):
```bash
git clone https://github.com/MariyanYordanov/kintales-infra.git
cd kintales-infra
cp .env.example .env  # Fill with saved production values
sudo bash setup/00-prerequisites.sh
# ... through 11-final-verification.sh
```
4. **Restore from USB backup**:
```bash
sudo mount /dev/sdc1 /mnt/backup-usb
sudo bash backup/restore.sh
```
5. **Deploy kintales-server**:
```bash
cd /data
git clone https://github.com/MariyanYordanov/kintales-server.git
cd kintales-server
cp .env.example .env  # Fill with production values
docker compose up -d
npm run db:migrate  # Migrations already applied in restore, but verify
```
6. **Verify**: Check all services, test API endpoints

### Prevention
- RAID 1 makes simultaneous failure extremely unlikely
- Monitor SMART data for early warning signs
- Keep USB backups current (weekly rotation)

## Scenario 3: Server Stolen or Destroyed

**Impact**: Full service outage + potential data breach
**Recovery time**: 1-3 days (new hardware + setup + restore)

### Immediate Actions
1. **Assess data breach risk** — LUKS encryption protects data at rest, but if server was running when stolen, RAM may contain sensitive data
2. **If personal data possibly exposed** → GDPR notification within 72 hours
3. **Rotate ALL secrets**: JWT, DB passwords, MinIO keys (from password manager)
4. **Report theft** to police (for insurance)

### Recovery Steps
1. **Purchase new hardware** (same ThinkPad T15G or equivalent)
2. **Run full setup** (same as Scenario 2, steps 2-6)
3. **Update DNS** if IP address changed
4. **Notify users** if data breach suspected (`incident-response/notify-users.sh`)

### Prevention
- Physical security (locked room, alarm system)
- Laptop lock cable (Kensington lock)
- Consider off-site backup to cloud (Backblaze B2) as additional protection

## Scenario 4: Power Outage

### Short Outage (< 2 hours)
**Impact**: None — laptop battery provides power
**Recovery**: Automatic — no action needed

### Long Outage (> 2 hours)
**Impact**: Server shuts down gracefully when battery depletes
**Recovery**: Automatic when power returns (BIOS: Boot on AC Restore)

**LUKS auto-unlock**: Server boots, LUKS unlocks via key file, RAID assembles, Docker starts
**Services auto-start**: Docker Compose with `restart: unless-stopped`

### Steps After Recovery
1. **Verify all services**: `docker compose ps`
2. **Check RAID status**: `cat /proc/mdstat`
3. **Check for data consistency**: `docker exec kintales-postgres pg_isready`
4. **Review logs**: `docker compose logs --tail 50`

### Prevention
- External UPS (APC Back-UPS 700VA, ~150 lv) extends runtime by 30-60 min
- UPS with USB monitoring can trigger graceful shutdown before battery dies

## Scenario 5: Network/ISP Outage

**Impact**: Service unreachable from internet
**Recovery**: Automatic when ISP restores service

### Steps
1. **Check if server is running**: Connect via local network (if available)
2. **Contact ISP**: Report outage
3. **If IP changed** (dynamic IP situations):
   - Update Cloudflare DNS A records
   - Consider getting static IP from ISP

### Prevention
- Static IP from ISP (avoids DNS update on IP change)
- Consider backup ISP (mobile hotspot for emergency SSH access)

## Scenario 6: Security Breach

See [incident-response/PLAYBOOK.md](../incident-response/PLAYBOOK.md) for detailed steps.

**Quick reference**:
1. `bash incident-response/emergency-shutdown.sh` — stop all services
2. `bash incident-response/audit-log-export.sh` — preserve evidence
3. Assess scope of breach
4. `bash incident-response/rotate-secrets.sh` — regenerate all credentials
5. Restore from last known clean backup
6. If personal data exposed: notify users within 72 hours (GDPR)

## Recovery Checklist Template

```
## Disaster Recovery — [Date] [Scenario]

### Assessment
- [ ] What happened: _______________
- [ ] When discovered: _______________
- [ ] Impact scope: _______________
- [ ] Data breach risk: YES / NO

### Recovery
- [ ] New hardware acquired (if needed)
- [ ] Fresh OS installed
- [ ] Setup scripts run (00-11)
- [ ] Backup restored from: _______________
- [ ] kintales-server deployed
- [ ] All services verified
- [ ] DNS updated (if needed)
- [ ] SSL certificates valid

### Post-Recovery
- [ ] Users notified (if breach)
- [ ] Root cause identified: _______________
- [ ] Preventive measures implemented: _______________
- [ ] Documentation updated

### Sign-off
Recovered by: _______________  Date: _______________
```

## Critical Information to Keep Accessible

Store these OUTSIDE the server (password manager, printed copy):

1. **GitHub credentials** (to clone repos)
2. **Cloudflare credentials** (to manage DNS)
3. **Production .env values** (all secrets)
4. **Backup GPG passphrase**
5. **LUKS recovery passphrase**
6. **ISP contact info** (for static IP issues)
7. **This checklist** (printed copy)
