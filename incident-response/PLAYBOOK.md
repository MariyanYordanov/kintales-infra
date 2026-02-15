# Incident Response Playbook

## Level 1: Service Down

**Symptoms**: API unreachable, Telegram alert for container down, users report errors.

### Diagnosis
```bash
# Check all containers
docker compose -f /data/kintales-server/docker-compose.yml ps

# Check which container is down
docker compose -f /data/kintales-server/docker-compose.yml logs --tail 50 [service]

# Check system resources
free -h          # RAM
df -h            # Disk space
cat /proc/mdstat # RAID health
```

### Resolution
```bash
# Restart specific service
docker compose -f /data/kintales-server/docker-compose.yml restart [service]

# If container keeps crashing, check logs
docker compose -f /data/kintales-server/docker-compose.yml logs --tail 200 [service]

# If out of memory
docker system prune -f  # Free Docker cache
# Consider increasing swap or reducing container memory limits

# If disk full
docker system prune -f  # Remove unused images/containers
# Check for log files: du -sh /data/docker/containers/*/
# Run backup cleanup: find /data/backups/daily/ -maxdepth 1 -mtime +30 -exec rm -rf {} \;

# If RAID degraded
cat /proc/mdstat  # Check which disk failed
# See docs/RAID-GUIDE.md for disk replacement
```

### If Data Corruption
```bash
# Stop all services
docker compose -f /data/kintales-server/docker-compose.yml down

# Restore from backup
sudo bash /root/kintales-infra/backup/restore.sh

# Restart services
docker compose -f /data/kintales-server/docker-compose.yml up -d
```

## Level 2: Suspected Security Breach

**Symptoms**: Unusual login attempts, unfamiliar processes, data anomalies, user reports of unauthorized access.

### Step 1: IMMEDIATE — Isolate

```bash
# Emergency shutdown — stops all services, blocks all ports except SSH
sudo bash /root/kintales-infra/incident-response/emergency-shutdown.sh
```

This preserves all evidence (logs, database state) while preventing further access.

### Step 2: ASSESS — Gather Evidence

```bash
# Export all logs for analysis
sudo bash /root/kintales-infra/incident-response/audit-log-export.sh
```

Review the exported logs:
- **Nginx access logs**: Unusual IPs, unusual endpoints, high request rates
- **pgAudit logs**: Unauthorized queries, mass data access
- **SSH auth logs**: Failed login attempts, successful logins from unknown IPs
- **Fail2ban logs**: Banned IPs, ban frequency

### Step 3: DECIDE — Is Personal Data Exposed?

**YES — Personal data accessed or exfiltrated**:
- Must notify Bulgarian Commission for Personal Data Protection (CPDP) within 72 hours
- Must notify affected users
- Document: what data, how many users, what happened

**NO — No personal data accessed**:
- Proceed to remediation

### Step 4: REMEDIATE — Fix and Secure

```bash
# Rotate ALL secrets
sudo bash /root/kintales-infra/incident-response/rotate-secrets.sh
```

Then:
1. Identify the vulnerability that was exploited
2. Patch/fix the vulnerability
3. Review all access logs for the past 30 days
4. Update firewall rules if needed
5. Check for backdoors (unauthorized SSH keys, cron jobs, Docker containers)

### Step 5: RESTORE — Return to Service

```bash
# If database compromised, restore from last known clean backup
sudo bash /root/kintales-infra/backup/restore.sh

# Start services
docker compose -f /data/kintales-server/docker-compose.yml up -d

# Re-enable firewall (emergency shutdown blocked everything)
sudo bash /root/kintales-infra/setup/05-firewall.sh
```

### Step 6: NOTIFY — If Data Breach

```bash
# Send notification to all registered users
sudo bash /root/kintales-infra/incident-response/notify-users.sh
```

### Step 7: POSTMORTEM

Document:
1. What happened (timeline)
2. How it was discovered
3. What was the impact
4. How was it resolved
5. What preventive measures are being implemented

## Level 3: Hardware Failure

See [docs/DISASTER-RECOVERY.md](../docs/DISASTER-RECOVERY.md) for detailed recovery procedures.

### Quick Reference

| Failure | Impact | Recovery Time |
|---------|--------|---------------|
| Single SSD | Zero downtime (RAID 1) | 1-2 hours |
| Both SSDs | Full outage | 4-8 hours |
| Server stolen | Full outage + possible breach | 1-3 days |
| Power outage (<2h) | None (battery) | Automatic |
| Power outage (>2h) | Server shutdown | Automatic on power restore |

## Contact Information

Keep this information accessible OUTSIDE the server:

- **ISP**: [Phone number] — for network issues
- **Hosting/Colo**: N/A (self-hosted)
- **Cloudflare**: https://dash.cloudflare.com — DNS management
- **Bulgarian CPDP**: https://www.cpdp.bg — data breach notification (72h deadline)
