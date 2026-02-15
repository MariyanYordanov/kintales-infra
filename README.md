# KinTales Infrastructure

Infrastructure as Code for the KinTales production server.

## Target Hardware

| Component | Spec |
|-----------|------|
| Machine | Lenovo ThinkPad T15G |
| CPU | Intel Core i7/i9 (6-8 cores) |
| RAM | 64 GB DDR4 |
| Storage | 2x SSD (RAID 1 mirror) |
| Network | 1 Gbps Ethernet |
| OS | Ubuntu Server 24.04 LTS |

## What This Does

Numbered setup scripts (`setup/00` through `setup/11`) transform a fresh Ubuntu Server install into a hardened, encrypted, monitored production server ready to host `kintales-server`.

## Quick Start

```bash
# 1. Clone this repo to the server
git clone https://github.com/MariyanYordanov/kintales-infra.git
cd kintales-infra

# 2. Create environment file
cp .env.example .env
nano .env  # Fill in all values

# 3. Run setup scripts in order
sudo bash setup/00-prerequisites.sh
sudo bash setup/01-lid-and-power.sh
sudo bash setup/02-os-hardening.sh
# ... see docs/ for LUKS and RAID guides ...
sudo bash setup/05-firewall.sh
sudo bash setup/06-fail2ban.sh
sudo bash setup/07-docker.sh
sudo bash setup/08-ssl-domain.sh
sudo bash setup/09-cloudflare-email.sh
sudo bash setup/10-monitoring.sh
sudo bash setup/11-final-verification.sh

# 4. Deploy kintales-server
cd /data
git clone https://github.com/MariyanYordanov/kintales-server.git
cd kintales-server
cp .env.example .env
nano .env  # Fill in production secrets
docker compose up -d
```

## Project Structure

```
kintales-infra/
├── setup/              # Numbered setup scripts (run in order)
├── backup/             # Automated backup & restore scripts
├── ssl/                # SSL certificate management
├── monitoring/         # Prometheus + Grafana + Alertmanager configs
├── postfix/            # Email server configs (future migration)
├── incident-response/  # Security incident scripts
├── maintenance/        # Monthly maintenance scripts
└── docs/               # Detailed guides for each component
```

## Setup Sequence

| Step | Script | What It Does |
|------|--------|-------------|
| 0 | `00-prerequisites.sh` | Verify hardware, install base packages |
| 1 | `01-lid-and-power.sh` | Ignore lid close, disable sleep |
| 2 | `02-os-hardening.sh` | SSH hardening, admin user, timezone |
| 3 | `03-luks-encryption.sh` | LUKS encryption guide (manual) |
| 4 | `04-raid-setup.sh` | RAID 1 mirror for 2x SSD |
| 5 | `05-firewall.sh` | UFW: Cloudflare-only + SSH whitelist |
| 6 | `06-fail2ban.sh` | Brute force protection |
| 7 | `07-docker.sh` | Docker Engine + Compose |
| 8 | `08-ssl-domain.sh` | Let's Encrypt wildcard SSL |
| 9 | `09-cloudflare-email.sh` | Cloudflare Email Routing |
| 10 | `10-monitoring.sh` | Prometheus + Grafana + Telegram |
| 11 | `11-final-verification.sh` | Full status report |

## Documentation

Detailed guides are in the `docs/` directory:

- [Hardware Setup](docs/HARDWARE-SETUP.md) — BIOS, physical placement
- [Network Setup](docs/NETWORK-SETUP.md) — Static IP, Cloudflare, DNS
- [LUKS Guide](docs/LUKS-GUIDE.md) — Full-disk encryption
- [RAID Guide](docs/RAID-GUIDE.md) — RAID 1 setup and recovery
- [Email Guide](docs/EMAIL-GUIDE.md) — Cloudflare routing, future Postfix
- [Monitoring Guide](docs/MONITORING-GUIDE.md) — Grafana dashboards, alerts
- [Backup Guide](docs/BACKUP-GUIDE.md) — USB rotation strategy
- [Disaster Recovery](docs/DISASTER-RECOVERY.md) — What to do when things break
- [Cost Breakdown](docs/COST-BREAKDOWN.md) — All running costs

## Security Model

- **Network**: Cloudflare proxy (DDoS protection), UFW blocks all non-Cloudflare traffic
- **SSH**: Key-only auth, non-standard port, admin IP whitelist
- **Storage**: LUKS encryption on both SSDs, RAID 1 redundancy
- **Monitoring**: Prometheus alerts via Telegram for anomalies
- **Backup**: Daily encrypted backups, USB rotation (one drive always off-site)

## License

Private project.
