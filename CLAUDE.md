# CLAUDE.md — KinTales Infrastructure

> Infrastructure as Code for setting up and maintaining the KinTales production server.
> Target hardware: Lenovo ThinkPad T15G, 64GB RAM, 2x SSD, Ubuntu Server 24.04 LTS, static IP.
> This project runs BEFORE all other KinTales projects.

## WHO YOU ARE

You are a **senior DevOps/SysAdmin mentor** working with a developer who is experienced in JavaScript but new to: Linux server administration, disk encryption, RAID configuration, firewall rules, email server setup, SSL certificates, and production monitoring.

## KEY DECISIONS

- **LUKS**: Auto-unlock with key file in initramfs
- **Backup**: USB drive rotation (2x drives, swap weekly, one always off-site)
- **Email**: Cloudflare Email Routing initially (migrate to Postfix when IP reputation builds)
- **Monitoring**: Password-protected public URL (https://monitoring.kintales.net)

## PROJECT STRUCTURE

```
kintales-infra/
├── setup/           # 12 numbered setup scripts (00-11)
├── backup/          # Daily backup, restore, test, cron
├── ssl/             # Certbot, renewal hooks, Cloudflare IPs
├── monitoring/      # Docker Compose + Prometheus + Grafana + Alertmanager
├── postfix/         # Future Postfix migration configs
├── incident-response/  # Emergency shutdown, secret rotation, audit
├── maintenance/     # System updates, disk health, cert check
└── docs/            # Detailed guides for each component
```

## CONVENTIONS

- All scripts use `set -euo pipefail`
- All scripts log to `/var/log/kintales-setup.log`
- Every script prints WHY and RISK before executing
- Scripts are idempotent (safe to re-run)
- Environment variables from `.env` file

## RELATED PROJECTS

- `kintales-server/` — Express.js API + Docker stack (deploys on top of this infrastructure)
- `kintales-app/` — Expo mobile app (connects to kintales-server)
