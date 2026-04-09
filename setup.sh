#!/bin/bash
set -e

# Dexi Anywhere - Setup Script
# Makes all Dexi services accessible over a Cloudflare tunnel via WiFi or 5G
#
# Usage: ./setup.sh <cloudflare-tunnel-token>
#
# Prerequisites:
#   - Raspberry Pi with Dexi stack running
#   - Internet connection (WiFi or 5G USB modem)
#   - Cloudflare tunnel created at https://one.dash.cloudflare.com
#   - Run this script ON the Pi (or SSH in first)

TUNNEL_TOKEN="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Validate ---

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "Usage: $0 <cloudflare-tunnel-token>"
    echo ""
    echo "Get your token from Cloudflare Zero Trust dashboard:"
    echo "  Networks → Tunnels → select tunnel → Install connector"
    echo "  Copy the token (starts with eyJ...)"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    error "Must run as root: sudo $0 $TUNNEL_TOKEN"
fi

# --- Step 1: Install cloudflared ---

if command -v cloudflared &>/dev/null; then
    info "cloudflared already installed: $(cloudflared --version)"
else
    info "Installing cloudflared..."
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$ARCH" in
        arm64|aarch64) ARCH="arm64" ;;
        armhf|armv7l)  ARCH="arm" ;;
        amd64|x86_64)  ARCH="amd64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"

    # Prefer WiFi for large downloads to avoid slow 5G speeds
    CURL_OPTS=""
    if ip link show wlan0 &>/dev/null && ip addr show wlan0 | grep -q "inet "; then
        CURL_OPTS="--interface wlan0"
        info "Downloading via WiFi interface"
    fi

    curl -L $CURL_OPTS -o /tmp/cloudflared "$DOWNLOAD_URL" || error "Download failed"
    install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared
    rm -f /tmp/cloudflared
    info "Installed cloudflared: $(cloudflared --version)"
fi

# --- Step 2: Move dexi-droneblocks to port 81 ---

if docker ps --format '{{.Names}} {{.Ports}}' | grep -q "dexi-droneblocks.*0.0.0.0:81->3000"; then
    info "dexi-droneblocks already on port 81:3000"
elif docker ps --format '{{.Names}}' | grep -q "dexi-droneblocks"; then
    info "Moving dexi-droneblocks to port 81..."
    IMAGE=$(docker inspect dexi-droneblocks --format '{{.Config.Image}}')
    docker stop dexi-droneblocks
    docker rm dexi-droneblocks
    docker run -d --name dexi-droneblocks -p 81:3000 --restart unless-stopped "$IMAGE"
    info "dexi-droneblocks now on port 81:3000"
else
    warn "dexi-droneblocks container not found — make sure it's running on port 81"
fi

# --- Step 3: Deploy nginx reverse proxy ---

NGINX_CONF="$SCRIPT_DIR/nginx/nginx.conf"
NGINX_DEST="/home/dexi/nginx"

if [ ! -f "$NGINX_CONF" ]; then
    error "nginx.conf not found at $NGINX_CONF"
fi

mkdir -p "$NGINX_DEST"
cp "$NGINX_CONF" "$NGINX_DEST/nginx.conf"

if docker ps --format '{{.Names}}' | grep -q '^nginx$'; then
    info "Restarting nginx container..."
    docker stop nginx && docker rm nginx
fi

# Pull via WiFi if available
if ip link show wlan0 &>/dev/null && ip addr show wlan0 | grep -q "inet "; then
    info "Pulling nginx image via WiFi..."
    WIFI_GW=$(ip route show dev wlan0 | grep default | awk '{print $3}')
    # Temporarily boost WiFi priority for the pull
    ip route replace default via "$WIFI_GW" dev wlan0 metric 50 2>/dev/null || true
    docker pull nginx:latest
    ip route replace default via "$WIFI_GW" dev wlan0 metric 600 2>/dev/null || true
fi

docker run -d --name nginx \
    --network host \
    -v "$NGINX_DEST/nginx.conf:/etc/nginx/nginx.conf:ro" \
    --restart unless-stopped \
    nginx

info "nginx reverse proxy running on port 80"

# --- Step 4: Configure route metrics (if 5G modem detected) ---

# Check if a USB cellular modem is present
if ip link show eth1 &>/dev/null && grep -q "cdc_ether" /sys/class/net/eth1/device/uevent 2>/dev/null; then
    info "5G modem detected on eth1"
    WIFI_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep wlan0 | cut -d: -f1)
    if [ -n "$WIFI_CONN" ]; then
        CURRENT_METRIC=$(nmcli -g ipv4.route-metric connection show "$WIFI_CONN")
        if [ "$CURRENT_METRIC" != "600" ]; then
            nmcli connection modify "$WIFI_CONN" ipv4.route-metric 600
            info "WiFi metric set to 600 (5G modem takes priority for tunnel)"
        else
            info "WiFi metric already set to 600"
        fi
    fi
else
    info "No 5G modem detected — tunnel will run over WiFi"
fi

# --- Step 5: Set up cloudflared systemd service ---

info "Configuring cloudflared service..."

cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel run --token ${TUNNEL_TOKEN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

# Wait for tunnel to connect
sleep 3
if systemctl is-active cloudflared &>/dev/null; then
    info "Cloudflare tunnel is running"
else
    warn "cloudflared may still be starting — check: systemctl status cloudflared"
fi

# --- Done ---

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Dexi Anywhere - Setup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Services available through your Cloudflare tunnel:"
echo "  /           → DroneBlocks      (port 81)"
echo "  /nodered/   → Node-RED         (port 1880)"
echo "  /vscode/    → VS Code          (port 9999)"
echo "  /ros/       → ROS Web UI       (port 8080)"
echo "  /rosbridge  → ROSBridge WS     (port 9090)"
echo ""
echo "To check status:  systemctl status cloudflared"
echo "To view logs:     journalctl -u cloudflared -f"
echo "To stop tunnel:   systemctl stop cloudflared"
