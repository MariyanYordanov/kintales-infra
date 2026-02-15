#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 10: Monitoring (Prometheus + Grafana + Telegram)
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [10-monitoring] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }
fail() { echo "  ❌ $1"; log "FAIL: $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 10: Monitoring Stack"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: Without monitoring, you won't know when:"
echo "     • A disk is 90% full (until it's 100% and services crash)"
echo "     • RAM is exhausted (until OOM killer starts terminating)"
echo "     • A container crashed (until users report errors)"
echo "     • SSL certificate expired (until browsers show errors)"
echo "     • Backup failed (until you need to restore and can't)"
echo ""
echo "     We deploy:"
echo "     • Prometheus — collects metrics every 15 seconds"
echo "     • Grafana    — beautiful dashboards at monitoring.kintales.net"
echo "     • Alertmanager — sends Telegram alerts when thresholds exceeded"
echo "     • Node Exporter — provides OS metrics (CPU, RAM, disk, network)"
echo ""
echo "RISK WITHOUT THIS: Silent failures. The server could be failing"
echo "     for hours or days before anyone notices."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

# ─── Load .env ───────────────────────────────────────

if [ ! -f "$ENV_FILE" ]; then
  fail ".env not found. Copy .env.example to .env."
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  fail "GRAFANA_ADMIN_PASSWORD not set in .env"
fi

log "Starting monitoring stack deployment"

# ─── Check: Docker installed ────────────────────────

if ! command -v docker &>/dev/null; then
  fail "Docker not installed. Run setup/07-docker.sh first."
fi

# ─── Prepare monitoring directory ────────────────────

echo "Preparing monitoring configuration..."

MONITORING_DIR="/data/monitoring"
mkdir -p "$MONITORING_DIR"

# Copy configs from infra repo to /data/monitoring
cp -r "${SCRIPT_DIR}/monitoring/"* "$MONITORING_DIR/"

ok "Monitoring configs copied to $MONITORING_DIR"

# ─── Update Alertmanager config with Telegram creds ──

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  sed -i \
    -e "s|\${TELEGRAM_BOT_TOKEN}|$TELEGRAM_BOT_TOKEN|g" \
    -e "s|\${TELEGRAM_CHAT_ID}|$TELEGRAM_CHAT_ID|g" \
    "$MONITORING_DIR/alertmanager/alertmanager.yml"
  ok "Alertmanager configured with Telegram credentials"
else
  echo "  ⚠️  TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set."
  echo "     Alerts won't be sent via Telegram."
  echo "     Set these in .env and re-run this script."
fi

# ─── Update Grafana password ────────────────────────

export GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD"

# ─── Deploy monitoring stack ────────────────────────

echo ""
echo "Deploying monitoring stack with Docker Compose..."

cd "$MONITORING_DIR"
docker compose -f docker-compose.monitoring.yml up -d

ok "Monitoring containers started"

# ─── Wait for services ──────────────────────────────

echo ""
echo "Waiting for services to become healthy..."

for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:3001/api/health 2>/dev/null; then
    ok "Grafana is ready"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  ⚠️  Grafana did not start within 60 seconds."
    echo "     Check: docker logs grafana"
  fi
  sleep 2
done

for i in $(seq 1 15); do
  if curl -s -o /dev/null http://localhost:9090/-/ready 2>/dev/null; then
    ok "Prometheus is ready"
    break
  fi
  sleep 2
done

# ─── Test Telegram alert ────────────────────────────

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  echo ""
  echo "Sending test Telegram message..."

  RESULT=$(curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=🔔 KinTales Monitoring: Test alert — monitoring stack deployed successfully on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S')" \
    -d "parse_mode=HTML" | jq -r '.ok' 2>/dev/null || echo "false")

  if [ "$RESULT" = "true" ]; then
    ok "Test Telegram message sent — check your Telegram!"
  else
    echo "  ⚠️  Telegram message failed. Check bot token and chat ID."
  fi
fi

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 10 Complete — Monitoring Active"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Services:"
echo "    Prometheus:    http://localhost:9090"
echo "    Grafana:       http://localhost:3001"
echo "    Alertmanager:  http://localhost:9093"
echo "    Node Exporter: http://localhost:9100"
echo ""
echo "  Grafana access:"
echo "    URL:      https://monitoring.${DOMAIN:-kintales.net}"
echo "    User:     admin"
echo "    Password: (from GRAFANA_ADMIN_PASSWORD in .env)"
echo ""
echo "  Alerts:"
echo "    Telegram: $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "configured" || echo "NOT configured")"
echo ""
echo "  See: docs/MONITORING-GUIDE.md for dashboard details"
echo ""
echo "  Next step: sudo bash setup/11-final-verification.sh"
echo ""

log "Step 10 completed successfully"
