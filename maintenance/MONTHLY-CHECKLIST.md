# Monthly Server Maintenance Checklist

Print this checklist and complete it on the 1st of each month.

```
## Monthly Maintenance — Date: _______________

### Security
- [ ] Install security patches: `sudo bash maintenance/update-system.sh`
- [ ] Review Fail2ban: `fail2ban-client status` — suspicious patterns?
- [ ] Review SSH logs: `grep "Failed" /var/log/auth.log | tail -50`
- [ ] Check Cloudflare firewall events (dashboard)
- [ ] Update Cloudflare IPs: `sudo bash ssl/cloudflare-ips-update.sh`

### Backup
- [ ] Verify automated test ran: check Telegram for monthly test notification
- [ ] Manual test (if auto-test missed): `sudo bash backup/test-restore.sh`
- [ ] Check backup files exist: `ls -la /data/backups/daily/ | tail -5`
- [ ] Verify USB drive has recent backups: `ls -la /mnt/backup-usb/kintales/daily/ | tail -5`
- [ ] Both USB drives tested (swap and check each)

### Disk & RAID
- [ ] RAID health: `cat /proc/mdstat` — must show [UU]
- [ ] SMART check: `sudo bash maintenance/disk-health-check.sh`
- [ ] Disk space: `df -h` — must be < 80%
- [ ] MinIO storage check

### SSL
- [ ] Certificate expiry: `sudo bash maintenance/certificate-check.sh` — > 30 days?
- [ ] Certbot logs: `sudo certbot certificates`

### Docker
- [ ] Container health: `docker compose -f /data/kintales-server/docker-compose.yml ps`
- [ ] Container logs: `docker compose logs --since 720h | grep -i error | head -20`
- [ ] Prune unused: `docker system prune -f`

### Monitoring
- [ ] Grafana accessible: https://monitoring.kintales.net
- [ ] All Prometheus targets UP
- [ ] Send test Telegram alert
- [ ] Review triggered alerts from past month

### Performance
- [ ] Average CPU: should be < 30% (check Grafana)
- [ ] Average RAM: should be < 50% (check Grafana)
- [ ] PostgreSQL slow queries: check `pg_stat_statements`

### Physical
- [ ] Server temperature normal (not hot to touch)
- [ ] Ethernet cable secure
- [ ] Battery health (check with `upower -i /org/freedesktop/UPower/devices/battery_BAT0`)
- [ ] Clean dust from vents (every 6 months)

### Sign-off
Completed by: _______________  Date: _______________
```
