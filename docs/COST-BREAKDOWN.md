# Cost Breakdown

## Fixed Costs

| Item | Cost | Frequency | Notes |
|------|------|-----------|-------|
| Domain (Cloudflare Registrar) | ~20 lv | Per year | kintales.net |
| Apple Developer Program | ~180 lv ($99) | Per year | Required for iOS App Store |
| Google Play Console | ~45 lv ($25) | One-time | Required for Play Store |

## Running Costs

| Item | Cost | Frequency | Notes |
|------|------|-----------|-------|
| Electricity (ThinkPad ~50W avg) | ~15-20 lv | Per month | 24/7 operation |
| Internet | 0 lv | — | Already have home internet |
| Cloudflare (free plan) | 0 lv | — | DNS, CDN, DDoS protection |
| Let's Encrypt | 0 lv | — | SSL certificates |
| Docker | 0 lv | — | Community Edition |
| All server software | 0 lv | — | PostgreSQL, MinIO, Nginx, etc. |

## Optional Costs

| Item | Cost | Frequency | Notes |
|------|------|-----------|-------|
| External UPS (APC 700VA) | ~150 lv | One-time | Extended power protection |
| 2x USB backup drives (500GB) | ~100 lv | One-time | For backup rotation |
| Backblaze B2 cloud backup | ~12 lv ($6/TB) | Per month | Additional off-site backup |
| NAS (Synology DS224+ w/ disks) | ~500-700 lv | One-time | Automated local backup |

## Annual Summary

### Minimum
```
Domain:        20 lv
Electricity:   200 lv (12 × ~17 lv)
───────────────────────
Total:         220 lv/year + Apple Dev 180 lv = 400 lv/year
```

### Recommended (with backups)
```
Domain:        20 lv
Electricity:   200 lv
Apple Dev:     180 lv
USB drives:    100 lv (one-time, year 1 only)
───────────────────────
Year 1:        500 lv
Year 2+:       400 lv/year
```

## Comparison with Cloud Hosting

| Approach | Annual Cost | Control | Data Location |
|----------|------------|---------|---------------|
| **Self-hosted (ours)** | ~400 lv | Full | Bulgaria |
| Supabase Pro + Vercel Pro | ~1,000 lv ($50/mo) | Limited | US/EU |
| AWS (EC2 + RDS + S3) | ~1,500+ lv | Medium | EU |
| Hetzner VPS + managed DB | ~600 lv | Medium | Germany |

**Self-hosting saves ~600-1,100 lv/year** compared to cloud alternatives, with full control over data and infrastructure.

## When to Consider Cloud Migration

- If electricity costs rise significantly
- If you need 99.99% uptime (our target: 99.5%)
- If user base grows beyond what single server can handle
- If maintenance time exceeds 4 hours/month consistently
