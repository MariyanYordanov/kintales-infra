#!/usr/bin/env bash
set -euo pipefail

# Weekly Cloudflare IP update for UFW firewall
# Scheduled via cron (setup/05-firewall.sh)

LOGFILE="/var/log/kintales-cloudflare-ips.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"; }

log "Starting Cloudflare IP update"

# Fetch current IPs
CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6)

if [ -z "$CF_IPV4" ]; then
  log "ERROR: Failed to fetch Cloudflare IPs"
  exit 1
fi

# Remove existing Cloudflare rules
ufw status numbered | grep "Cloudflare" | awk -F'[][]' '{print $2}' | sort -rn | while read -r num; do
  echo "y" | ufw delete "$num" 2>/dev/null || true
done

log "Removed old Cloudflare rules"

# Add updated IPv4 ranges
COUNT=0
while IFS= read -r ip; do
  if [ -n "$ip" ]; then
    ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare" 2>/dev/null || true
    COUNT=$((COUNT + 1))
  fi
done <<< "$CF_IPV4"

# Add updated IPv6 ranges
while IFS= read -r ip; do
  if [ -n "$ip" ]; then
    ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare" 2>/dev/null || true
    COUNT=$((COUNT + 1))
  fi
done <<< "$CF_IPV6"

log "Added $COUNT Cloudflare IP ranges"
echo "✅ Updated $COUNT Cloudflare IP ranges in UFW"
