# DEXI Anywhere

Access your DEXI drone remotely through a Cloudflare Tunnel. Works over WiFi, 5G, or both.

## What You Need

- **DEXI drone** with Raspberry Pi running the DEXI stack
- **Internet connection** — one or both of:
  - **WiFi** with internet access (your existing setup)
  - **5G USB modem**: [TCL LINKPORT IK511](https://us.tcl.com/products/linkport-ik511) with an active SIM / data plan — plug and play, no drivers needed
- **Cloudflare account** (free tier) with a domain (~$12/year if you don't have one)

## How It Works

```
Internet → Cloudflare Tunnel → nginx (port 80) → Local Services
                  ↑                   ├─ /           → DroneBlocks  (:81 → :3000)
            WiFi or 5G               ├─ /nodered/   → Node-RED     (:1880)
                                     ├─ /vscode/    → VS Code      (:9999)
                                     ├─ /ros/       → ROS Web UI   (:8080)
                                     └─ /rosbridge  → ROSBridge WS (:9090)
```

A Cloudflare Tunnel gives you a public HTTPS URL to access all DEXI services from anywhere — your laptop, phone, or tablet. The tunnel runs over whatever internet connection is available.

**When both WiFi and 5G are connected:**
- **5G is preferred** for the tunnel (route metric 100)
- WiFi (metric 600) stays available for local SSH and large file transfers
- If 5G drops, the tunnel automatically falls back to WiFi

**WiFi only:** The tunnel runs entirely over WiFi. No modem needed.

**5G only (field use):** Take the drone outside with no WiFi — everything runs over 5G automatically.

## Step 1: Connect to the Internet

### Option A: WiFi Only

If your Pi is already connected to WiFi with internet access, skip to [Step 2](#step-2-create-a-cloudflare-tunnel).

### Option B: 5G Modem

1. Insert SIM card into the modem and power it on to verify you have signal (LED indicators on the modem)
2. Plug the modem into any USB port on the Pi
3. Wait ~30 seconds — the modem appears as a network interface automatically (no drivers needed)
4. Verify via SSH:
```bash
# Check the modem is detected
lsusb | grep "1bbb"
# Should show: T & A Mobile Phones Dongle

# Check it has an IP
ip addr show eth1
# Look for an "inet" line like: inet 192.168.0.x/24
```

> **Note:** If the Pi is also on WiFi, you can verify on the DEXI dashboard at `http://<pi-wifi-ip>/status` — the **Cellular** card will show **Connected** with the modem's IP address.

## Step 2: Create a Cloudflare Tunnel

1. Sign up at [cloudflare.com](https://cloudflare.com) (free tier works)
2. Add a domain and point its nameservers to Cloudflare
3. Go to **Zero Trust** → **Networks** → **Tunnels** → **Create a Tunnel**
4. Select **cloudflared** type and name your tunnel (e.g. `my-dexi`)
5. Add a **Public Hostname**:
   - Subdomain: e.g. `dexi`
   - Domain: your domain
   - Service type: `HTTP`
   - URL: `localhost`
6. Copy the tunnel token (starts with `eyJ...`) — you'll need this in the next step

## Step 3: Run the Setup Script

SSH into the Pi and run:

```bash
git clone https://github.com/dbaldwin/dexi-anywhere.git ~/dexi-anywhere
cd ~/dexi-anywhere
sudo ./setup.sh <your-tunnel-token>
```

The script automatically:
- Installs `cloudflared` (downloads via WiFi if available)
- Moves the DroneBlocks dashboard behind an nginx reverse proxy
- If a 5G modem is detected, sets WiFi route metric to 600 so 5G takes priority
- Creates a systemd service so everything survives reboot

## Step 4: Verify

Open your tunnel URL in a browser: `https://dexi.your-domain.com`

You should see the DroneBlocks dashboard. All services are accessible:

| Path | Service | Description |
|------|---------|-------------|
| `/` | DroneBlocks | Main flight dashboard |
| `/nodered/` | Node-RED | Visual programming |
| `/vscode/` | VS Code | Remote code editor |
| `/ros/` | ROS Web UI | ROS visualization |
| `/rosbridge` | ROSBridge | WebSocket bridge for ROS2 |

Check tunnel status on the Pi:
```bash
systemctl status cloudflared
```

## Node-RED Rosbridge Config

When using Node-RED through the tunnel, set the ROS2 Websocket Server URL to:

```
ws://172.17.0.1:9090
```

This is the Docker bridge gateway — it lets the Node-RED container reach rosbridge on the host.

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

## Troubleshooting

**Modem not detected:** Unplug and replug the USB modem. Check `lsusb` for the device. If `eth1` doesn't appear after 30 seconds, try a different USB port.

**No internet over 5G:** The modem has an IP but can't reach the internet. Check signal strength on the modem's LED indicators. Try `ping -I eth1 8.8.8.8` to test. Some carriers require APN configuration — contact your carrier if pings fail.

**502 Bad Gateway:** A backend service isn't running. Check `sudo docker ps` and verify the expected containers are up.

**Tunnel not connecting:** Check `sudo journalctl -u cloudflared -f` for errors. Verify the tunnel token is correct and the public hostname is configured in the Cloudflare dashboard.

**WebSocket errors (mixed content):** Make sure you're using `dexi-droneblocks` v0.13+ which automatically uses `wss://` over HTTPS.

**Slow downloads over 5G:** Force large downloads through WiFi instead:
```bash
curl --interface wlan0 -L -O <url>
```

## Supported 5G Hardware

Tested with **TCL LINKPORT IK511** (T-Mobile). Any USB modem that presents as a `cdc_ether` network interface should work, including common models from Huawei, ZTE, Quectel, and Sierra Wireless.

## License

MIT
