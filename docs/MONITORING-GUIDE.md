# Monitoring Guide

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Node Exporter│────▶│  Prometheus  │────▶│   Grafana    │
│ (OS metrics) │     │  (scraper)   │     │ (dashboards) │
└──────────────┘     └──────┬───────┘     └──────────────┘
┌──────────────┐           │              ┌──────────────┐
│ PG Exporter  │───────────┤              │ Alertmanager │
│ (DB metrics) │           │              │  (Telegram)  │
└──────────────┘           └─────────────▶└──────────────┘
┌──────────────┐
│   cAdvisor   │───────────┘
│(Docker stats)│
└──────────────┘
```

## Access

- **URL**: https://monitoring.kintales.net
- **Username**: admin
- **Password**: from `GRAFANA_ADMIN_PASSWORD` in `.env`

Grafana is behind Cloudflare proxy + Nginx reverse proxy. Protected by:
- Strong password
- Cloudflare DDoS protection
- Fail2ban HTTP jail
- HTTPS only

## Dashboards

### Server Overview
- CPU usage (cores, load average)
- RAM usage (used, cached, available)
- Disk I/O (read/write throughput)
- Network I/O (bandwidth, packets)
- System uptime
- Open file descriptors

### PostgreSQL Metrics
- Active connections (vs max_connections)
- Transactions per second
- Cache hit ratio (should be >99%)
- Table sizes
- Slow queries (>1s)
- Lock statistics
- Replication lag (when replica added)

### Docker Metrics
- Container CPU/RAM per service
- Container restart counts
- Network I/O per container
- Volume disk usage
- Container health status

## Alert Rules

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| Disk Space Warning | >80% used | warning | Check what's consuming space |
| Disk Space Critical | >90% used | critical | Immediate cleanup needed |
| CPU High | >90% for 5min | warning | Check running processes |
| RAM High | >85% used | warning | Check for memory leaks |
| RAID Degraded | RAID not [UU] | critical | Replace failed disk ASAP |
| Backup Failed | No backup in 25h | critical | Check backup script logs |
| SSL Expiring | <14 days to expiry | warning | Check certbot renewal |
| Container Down | Docker container exited | critical | Check container logs |
| PostgreSQL Down | PG exporter unreachable | critical | Check PostgreSQL container |

## Telegram Alerts

### Setup

1. Create Telegram bot: talk to [@BotFather](https://t.me/BotFather), use `/newbot`
2. Save the bot token to `.env` as `TELEGRAM_BOT_TOKEN`
3. Send a message to your bot (any text)
4. Get chat ID:
```bash
curl "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[0].message.chat.id'
```
5. Save chat ID to `.env` as `TELEGRAM_CHAT_ID`

### Alert Format

Telegram messages include:
- Alert name and severity
- Current value vs threshold
- Affected service
- Timestamp
- Direct link to Grafana dashboard

### Silencing Alerts

During planned maintenance, silence alerts:
```bash
# Via Alertmanager API
curl -X POST http://localhost:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{"matchers":[{"name":"alertname","value":".*","isRegex":true}],"startsAt":"2024-01-01T00:00:00Z","endsAt":"2024-01-01T02:00:00Z","createdBy":"admin","comment":"Planned maintenance"}'
```

## Adding Custom Metrics

### From kintales-server API

The `/health` endpoint returns metrics. Add to `prometheus.yml`:

```yaml
- job_name: 'kintales-api'
  metrics_path: /health
  static_configs:
    - targets: ['api:3000']
```

### Custom Alert Rules

Add to `prometheus/alert-rules.yml`:

```yaml
- alert: CustomAlertName
  expr: metric_name > threshold
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Description of what happened"
```

## Troubleshooting

### Grafana not accessible
1. Check container: `docker ps | grep grafana`
2. Check logs: `docker logs grafana`
3. Check Nginx proxy: `docker logs kintales-nginx`

### Prometheus not scraping
1. Check targets: Grafana → Explore → Prometheus → Status → Targets
2. Check config: `docker exec prometheus cat /etc/prometheus/prometheus.yml`
3. Check network: containers must be on same Docker network

### No Telegram alerts
1. Test bot: `curl "https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<ID>&text=test"`
2. Check Alertmanager config: `docker exec alertmanager cat /etc/alertmanager/alertmanager.yml`
3. Check Alertmanager logs: `docker logs alertmanager`
