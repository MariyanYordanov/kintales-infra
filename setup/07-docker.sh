#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  STEP 7: Docker Engine & Docker Compose
# ═══════════════════════════════════════════════════════

LOGFILE="/var/log/kintales-setup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [07-docker] $1" | tee -a "$LOGFILE"; }
ok()  { echo "  ✅ $1"; log "OK: $1"; }
fail() { echo "  ❌ $1"; log "FAIL: $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STEP 7: Docker Engine & Docker Compose"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "WHY: Docker isolates each service (PostgreSQL, MinIO, API, etc.)"
echo "     in its own container. This means:"
echo "     • Services can't interfere with each other"
echo "     • Easy to update, restart, or roll back individual services"
echo "     • Consistent environment (same in dev and production)"
echo "     • All kintales-server services are already containerized"
echo ""
echo "RISK WITHOUT THIS: You'd have to install PostgreSQL, MinIO,"
echo "     Node.js, Nginx, ClamAV, etc. directly on the OS. Updates"
echo "     become risky, conflicts are common, and rollback is painful."
echo ""
echo "NOTE: We install Docker from the official Docker repository,"
echo "     NOT the Ubuntu snap package. The snap version has"
echo "     limitations with file system access and networking."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

ADMIN_USER="${ADMIN_USER:-kintales}"

log "Starting Docker installation"

# ─── Check: Already installed ────────────────────────

if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version)
  echo "  Docker already installed: $DOCKER_VER"
  read -p "  Reinstall/update? (y/N): " REINSTALL
  if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
    ok "Docker already installed — skipping"
    echo ""
    echo "  Next step: sudo bash setup/08-ssl-domain.sh"
    exit 0
  fi
fi

# ─── Check: RAID mounted ────────────────────────────

if ! mountpoint -q /data 2>/dev/null; then
  echo "  ⚠️  /data is not mounted. Docker data will be stored"
  echo "     on the root filesystem instead of the RAID array."
  echo "     This is not recommended for production."
  read -p "     Continue anyway? (y/N): " CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    echo "  Run setup/04-raid-setup.sh first."
    exit 0
  fi
fi

# ─── Remove old versions ────────────────────────────

echo "Removing old Docker versions (if any)..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y "$pkg" 2>/dev/null || true
done

# ─── Add Docker's official GPG key ──────────────────

echo ""
echo "Adding Docker's official GPG key and repository..."
echo ""
echo "WHY: We add Docker's own apt repository to get the latest"
echo "     stable version directly from Docker, Inc. Ubuntu's"
echo "     built-in docker packages are often outdated."

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

ok "Docker repository added"

# ─── Install Docker ──────────────────────────────────

echo ""
echo "Installing Docker Engine, CLI, and Compose plugin..."
apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

ok "Docker installed: $(docker --version)"
ok "Compose installed: $(docker compose version)"

# ─── Configure Docker data-root ──────────────────────

echo ""
echo "Configuring Docker to store data on RAID array..."
echo ""
echo "WHY: By default, Docker stores everything in /var/lib/docker"
echo "     on the root filesystem. We move it to /data/docker so:"
echo "     • Container data is on the RAID 1 array (redundant)"
echo "     • LUKS encryption covers Docker data too"
echo "     • Separate from OS — disk full won't crash the OS"

mkdir -p /data/docker

cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

ok "Docker config: data-root=/data/docker, log max 10MB × 3 files"

# ─── Add admin user to docker group ──────────────────

echo ""
echo "Adding $ADMIN_USER to docker group..."
echo ""
echo "WHY: Without this, you'd need 'sudo' for every docker command."
echo "     Adding to the docker group lets the admin user run Docker"
echo "     directly. Note: this is equivalent to root access for"
echo "     Docker operations, which is acceptable for a dedicated"
echo "     server admin."

usermod -aG docker "$ADMIN_USER"
ok "$ADMIN_USER added to docker group (re-login required)"

# ─── Enable and start Docker ────────────────────────

echo ""
echo "Enabling Docker to start on boot..."
systemctl enable docker
systemctl enable containerd
systemctl restart docker

ok "Docker enabled and started"

# ─── Verify ──────────────────────────────────────────

echo ""
echo "Running verification (hello-world container)..."
docker run --rm hello-world 2>&1 | head -5

ok "Docker is working correctly"

# ─── Summary ─────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Step 7 Complete — Docker Installed"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Docker Engine: $(docker --version | awk '{print $3}' | tr -d ',')"
echo "  Compose:       $(docker compose version | awk '{print $4}')"
echo "  Data root:     /data/docker"
echo "  Log limit:     10MB × 3 files per container"
echo "  Auto-start:    enabled"
echo ""
echo "  ⚠️  $ADMIN_USER must re-login for docker group to take effect:"
echo "     exit && ssh -p ${SSH_PORT:-2222} $ADMIN_USER@[SERVER_IP]"
echo ""
echo "  Next step: sudo bash setup/08-ssl-domain.sh"
echo ""

log "Step 7 completed successfully"
