# DEXI Anywhere

Access your DEXI drone remotely using a Cloudflare Tunnel. Works over WiFi or 5G.

## Architecture

```
Internet → Cloudflare Tunnel → nginx (port 80) → Local Services
                  ↑                   ├─ /           → DroneBlocks  (:81 → :3000)
            WiFi or 5G               ├─ /nodered/   → Node-RED     (:1880)
                                      ├─ /vscode/    → VS Code      (:9999)
                                      ├─ /ros/       → ROS Web UI   (:8080)
                                      └─ /rosbridge  → ROSBridge WS (:9090)
```

## Prerequisites

- Raspberry Pi with DEXI stack running (DroneBlocks, Node-RED, rosbridge, etc.)
- Docker installed on the Pi
- Cloudflare account (free tier) with a domain

## Quick Start

### 1. Create a Cloudflare Tunnel

1. Sign up at [cloudflare.com](https://cloudflare.com) (free tier)
2. Add a domain (buy one for ~$12/year if needed) and point nameservers to Cloudflare
3. Go to **Zero Trust** → **Networks** → **Tunnels** → **Create a Tunnel**
4. Select **cloudflared** type, name your tunnel
5. Add a **Public Hostname**:
   - Subdomain: e.g. `dexi-anywhere`
   - Domain: your domain
   - Service type: `HTTP`
   - URL: `localhost`
6. Copy the tunnel token (starts with `eyJ...`)

### 2. Run the setup script

Clone this repo on the Pi and run:

```bash
git clone https://github.com/dbaldwin/dexi-anywhere.git ~/dexi-anywhere
cd ~/dexi-anywhere
sudo ./setup-5g.sh <your-tunnel-token>
```

The script:
- Installs cloudflared (downloads via WiFi if available)
- Moves dexi-droneblocks to port 81 behind nginx
- Deploys the nginx reverse proxy on port 80
- Creates a systemd service so everything survives reboot

### 3. Verify

Open `https://your-subdomain.your-domain.com` in a browser.

Check status on the Pi:
```bash
systemctl status cloudflared
sudo docker ps
```

## Services

| Path | Service | Description |
|------|---------|-------------|
| `/` | DroneBlocks | Main flight dashboard |
| `/nodered/` | Node-RED | Visual programming for drone |
| `/vscode/` | VS Code | Remote code editor |
| `/ros/` | ROS Web UI | ROS visualization (port 8080) |
| `/rosbridge` | ROSBridge | WebSocket bridge for ROS2 |

## 5G Modem Setup (Optional)

For field use without WiFi, add a USB 5G modem to the Pi. The setup script handles everything — just plug in the modem before running it.

### Supported hardware

Tested with TCL LINKPORT IK511 (T-Mobile). Any USB modem that presents as a `cdc_ether` network interface should work.

### Setup

1. Plug the modem into a USB port on the Pi
2. Verify it's detected:
   ```bash
   lsusb | grep -i "mobile\|modem\|1bbb"
   ip addr show eth1
   ```
3. Run the same setup script from [Quick Start](#2-run-the-setup-script) — it detects the 5G modem and configures routing automatically

The tunnel uses whichever connection is available. When both WiFi and 5G are connected, 5G (metric 100) takes priority for the tunnel while WiFi (metric 600) remains available for local SSH and large downloads. When you take the Pi outside with no WiFi, the tunnel runs entirely over 5G.

## Node-RED Rosbridge Config

When using Node-RED through the tunnel, set the ROS2 Websocket Server URL to:

```
ws://172.17.0.1:9090
```

This is the Docker bridge gateway — it lets the Node-RED container reach rosbridge on the host. This address is the same on all standard Docker installations.

## How It Works

**WebSocket handling:** Pages served over HTTPS through the tunnel use `wss://` and route WebSocket connections through nginx at `/rosbridge`. Local HTTP access still uses `ws://hostname:9090` directly. This is handled automatically in `dexi-droneblocks` v0.13+.

**Reboot tolerance:** cloudflared runs as a systemd service, all Docker containers use `--restart unless-stopped`, and network metrics are persisted in NetworkManager.

## Troubleshooting

**502 Bad Gateway:** A backend service isn't running. Check `sudo docker ps` and verify the expected containers are up.

**Tunnel not connecting:** Check `sudo journalctl -u cloudflared -f` for errors. Verify the tunnel token is correct and the public hostname is configured in Cloudflare dashboard.

**WebSocket errors (mixed content):** Make sure you're using `dexi-droneblocks` v0.13+ which automatically uses `wss://` over HTTPS. Older versions hardcode `ws://hostname:9090` which browsers block on HTTPS pages.

**Slow downloads over 5G:** Force downloads through WiFi:
```bash
curl --interface wlan0 -L -O <url>
```

## Managing the Tunnel

```bash
# Check status
systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -f

# Restart
sudo systemctl restart cloudflared

# Stop (disable remote access)
sudo systemctl stop cloudflared
```

## License

MIT
