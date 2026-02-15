# Hardware Setup — Lenovo ThinkPad T15G

## BIOS Settings

Access BIOS: Power on → press F1 repeatedly

### Required Changes

| Setting | Value | Location | Why |
|---------|-------|----------|-----|
| Boot on AC | Enabled | Config → Power | Auto-restart after power outage |
| Lid Close Action | Do Nothing | Config → Power | Server continues when lid closed |
| Wake on LAN | Enabled | Config → Network | Remote wake capability |
| Secure Boot | Enabled | Security → Secure Boot | Prevent boot-time tampering |
| USB Boot | Disabled | Security → Boot | Prevent unauthorized boot from USB |
| Intel VT-x | Enabled | Security → Virtualization | Docker performance |
| Intel VT-d | Enabled | Security → Virtualization | Device passthrough |

### BIOS Password

Set a BIOS supervisor password to prevent unauthorized changes:
- Security → Password → Supervisor Password

**Store this password securely** — losing it requires a motherboard reset.

## Physical Setup

### Placement
- Well-ventilated area (laptop generates heat under load)
- Stable surface, away from direct sunlight
- Away from water sources (pipes, windows)
- Accessible for maintenance (dust cleaning every 6 months)

### Connections
- **Ethernet**: Cat 6 cable directly to router/switch (NOT WiFi)
- **Power**: Connected to wall outlet (or UPS if available)
- **Lid**: Keep open slightly (2-3 cm) for airflow, or fully open
- **USB**: One port reserved for backup USB drive

### Battery as UPS
The internal laptop battery provides 2-4 hours of runtime under server load. This protects against:
- Brief power outages (seconds to minutes)
- Power fluctuations and surges
- Time to gracefully shutdown if extended outage

**Optional**: External UPS (APC Back-UPS 700VA, ~150 lv) adds:
- Additional 30-60 minutes of runtime
- Surge protection for connected equipment
- USB monitoring for automatic graceful shutdown

## Network Requirements

- **Ethernet**: 1 Gbps connection to router
- **Router**: Port forwarding configured:
  - Port 80 → server IP
  - Port 443 → server IP
  - Port 2222 → server IP (SSH)
- **Static IP**: Contact ISP for static IP address
- **DNS**: Domain pointed to static IP via Cloudflare

See [NETWORK-SETUP.md](NETWORK-SETUP.md) for detailed network configuration.

## Thermal Management

Monitor temperatures with:
```bash
sensors  # CPU temperature
hddtemp /dev/sda /dev/sdb  # SSD temperatures
```

**Warning thresholds**:
- CPU > 80°C sustained → check airflow
- SSD > 60°C → check placement

**Cleaning schedule**: Every 6 months, use compressed air to clean vents and fans.

## Disk Configuration

| Slot | Device | Purpose |
|------|--------|---------|
| SSD 1 | /dev/sda | RAID 1 member (LUKS encrypted) |
| SSD 2 | /dev/sdb | RAID 1 member (LUKS encrypted) |
| USB | /dev/sdc | Backup drive (mounted at /mnt/backup-usb) |

See [LUKS-GUIDE.md](LUKS-GUIDE.md) and [RAID-GUIDE.md](RAID-GUIDE.md) for setup.
