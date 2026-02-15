# Network Setup

## Prerequisites

1. **Static IP from ISP** — contact your ISP to request a static IP address
2. **Domain purchased** — kintales.net (via Cloudflare Registrar or transferred to Cloudflare)
3. **Cloudflare account** — free plan is sufficient

## Step 1: Static IP Configuration

### On the Server (Ubuntu 24.04)

Ubuntu 24.04 uses Netplan for network configuration.

```bash
# Check current network interface name
ip link show
# Typically: enp0s31f6 or eno1 for ThinkPad Ethernet
```

Edit `/etc/netplan/01-netconfig.yaml`:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s31f6:  # Replace with your interface name
      dhcp4: false
      addresses:
        - 192.168.1.100/24  # Your local static IP
      routes:
        - to: default
          via: 192.168.1.1  # Your router IP
      nameservers:
        addresses:
          - 1.1.1.1  # Cloudflare DNS
          - 1.0.0.1
```

Apply:
```bash
sudo netplan apply
```

### On the Router

Configure port forwarding:

| External Port | Internal IP | Internal Port | Protocol |
|--------------|-------------|---------------|----------|
| 80 | 192.168.1.100 | 80 | TCP |
| 443 | 192.168.1.100 | 443 | TCP |
| 2222 | 192.168.1.100 | 2222 | TCP |

**Disable WiFi** on the server — use Ethernet only.

## Step 2: Cloudflare DNS Setup

### Add Domain to Cloudflare

1. Log into [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Add site → enter `kintales.net`
3. Select Free plan
4. If domain is not at Cloudflare Registrar, update nameservers at your registrar

### DNS Records

Create these DNS records:

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `kintales.net` | `[STATIC_IP]` | Proxied | Auto |
| A | `api.kintales.net` | `[STATIC_IP]` | Proxied | Auto |
| A | `monitoring.kintales.net` | `[STATIC_IP]` | Proxied | Auto |
| CNAME | `www.kintales.net` | `kintales.net` | Proxied | Auto |

### Cloudflare Settings

**SSL/TLS:**
- Encryption mode: **Full (strict)** — we have our own Let's Encrypt cert
- Always Use HTTPS: ON
- Minimum TLS Version: 1.2

**Security:**
- Security Level: Medium
- Challenge Passage: 30 minutes
- Browser Integrity Check: ON

**Speed:**
- Auto Minify: OFF (API server, not static site)

## Step 3: Cloudflare API Token

Create an API token for Let's Encrypt DNS challenge:

1. Go to [Cloudflare Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create Token → Custom Token
3. Permissions: Zone → DNS → Edit
4. Zone Resources: Include → Specific zone → kintales.net
5. Create Token
6. Save token in `.env` as `CLOUDFLARE_API_TOKEN`

## Step 4: Verify

```bash
# Test DNS resolution
dig +short kintales.net
dig +short api.kintales.net

# Test external access (after port forwarding)
curl -I https://kintales.net

# Test from outside your network (use phone mobile data)
curl -I https://api.kintales.net/health
```

## Troubleshooting

### "Connection refused" from outside
- Check router port forwarding rules
- Verify UFW allows the ports: `sudo ufw status`
- Test from inside network first: `curl http://192.168.1.100`

### DNS not resolving
- Wait 5-10 minutes for Cloudflare propagation
- Check: `dig kintales.net @1.1.1.1`
- Verify A record in Cloudflare dashboard

### Cloudflare 522 error (Connection timed out)
- Server is not responding on port 443
- Check Nginx is running: `docker ps | grep nginx`
- Check firewall: `sudo ufw status`
