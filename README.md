# DEXI Drone Remote Access Setup

Access your DEXI drone from anywhere using Cloudflare Tunnel and nginx reverse proxy.

## Architecture Overview

```
Internet → Cloudflare Tunnel → nginx (port 80) → Local Services
                                      ├─> dexi-droneblocks (port 81)
                                      ├─> ROS Service (port 8080)
                                      ├─> Node-RED (port 1880)
                                      ├─> VS Code (port 9999)
                                      └─> ROSBridge (port 9090)
```

## Prerequisites

- Raspberry Pi with DEXI drone software installed
- Docker and Docker Compose installed on the Pi
- Cloudflare account (free tier)
- Domain name (can purchase for ~$12/year)

## Quick Start

### 1. Cloudflare Setup

1. **Create Cloudflare Account**
   - Sign up at [cloudflare.com](https://cloudflare.com) (free tier)

2. **Add Your Domain**
   - Add your domain to Cloudflare
   - Update your domain's nameservers to Cloudflare's nameservers
   - Wait for DNS propagation (~5-10 minutes)

3. **Create Cloudflare Tunnel**
   - Go to Cloudflare dashboard
   - Navigate to **Zero Trust** section (may need to sign up for free tier)
   - Go to **Networks** → **Tunnels** → **Create a Tunnel**
   - Select **cloudflared** type
   - Name your tunnel (e.g., `cm5-droneblocks-shop`)
   - Copy the installation command provided by Cloudflare

4. **Install cloudflared on Raspberry Pi**
   ```bash
   # Download and install cloudflared
   curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
   sudo dpkg -i cloudflared.deb
   ```

5. **Configure Public Hostname in Cloudflare**
   - In the tunnel configuration, go to the **Public Hostname** tab
   - Click **Add a public hostname**
   - **Hostname**: Enter your full domain (e.g., `norman.dronepan.com`)
   - **Service Type**: HTTP
   - **URL**: `localhost:80`
   - Click **Save**

   This routes traffic from your domain through the tunnel to nginx on port 80.

### 2. Setup Project on Raspberry Pi

Clone this repository:

```bash
cd ~
git clone <this-repo-url> dexi-anywhere
cd dexi-anywhere
```

Project structure:
```
dexi-anywhere/
├── nginx/
│   └── nginx.conf           # Nginx reverse proxy configuration
└── docker-compose.yaml      # Docker services definition
```

### 3. Start Docker Services

```bash
# Start DEXI DroneBlocks and nginx
docker compose up -d
```

This will:
- Pull the `droneblocks/dexi-droneblocks:anywhere` image
- Start DEXI DroneBlocks on port 81
- Start nginx reverse proxy on port 80

### 4. Start Cloudflare Tunnel

Run the tunnel using the command from your Cloudflare dashboard:

```bash
cloudflared tunnel run --token <YOUR_TOKEN>
```

Keep this running in a terminal, or install it as a service:

```bash
# Install as system service (optional, for auto-start on boot)
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

### 5. Verify Setup

Check that all services are running:

```bash
docker compose ps
```

You should see:
- `dexi-droneblocks` running on port 81
- `nginx` running with host network mode

Test local access:
```bash
curl http://localhost
```

Test remote access:
```
https://your-domain.com
```

## Service URLs

Once deployed, you can access the following services remotely:

| Service | URL Path | Local Port |
|---------|----------|------------|
| DEXI DroneBlocks | `/` | 81 |
| ROS Web Interface | `/ros/` | 8080 |
| Node-RED | `/nodered/` | 1880 |
| VS Code | `/vscode/` | 9999 |
| ROSBridge | `/rosbridge/` | 9090 |

Example: If your domain is `dexi.example.com`, access Node-RED at `https://dexi.example.com/nodered/`

## Configuration

### Nginx Reverse Proxy

The nginx configuration (`nginx/nginx.conf`) routes incoming requests to the appropriate local services. It handles:
- WebSocket upgrades (required for ROS, VS Code, ROSBridge)
- Path-based routing
- HTTP/1.1 protocol
- SSL/TLS termination (handled by Cloudflare)

### Docker Compose

The `docker-compose.yaml` defines:
- **dexi-droneblocks**: Main application using pre-built image `droneblocks/dexi-droneblocks:anywhere`
  - Port mapping: `81:80` (host:container)
  - Exposed on port 81 to avoid conflicts with nginx
- **nginx**: Reverse proxy (uses host network for direct port 80 access)

### Port Mapping Explained

- **Port 81:80** in docker-compose means:
  - Format: `host:container`
  - DEXI app runs on port 80 inside the container
  - Accessible on port 81 from the Raspberry Pi
  - Port 81 avoids conflicts with nginx (which uses port 80)

### How Traffic Flows

```
1. User browses to https://your-domain.com
2. Cloudflare receives HTTPS request (port 443)
3. Cloudflare Tunnel forwards to localhost:80 on Pi
4. Nginx receives request on port 80
5. Nginx proxies to appropriate service (e.g., localhost:81 for main app)
```

### WebSocket and SSL/TLS

**Important:** When your DEXI app needs to connect to WebSocket services (like ROSBridge):

- External URL is HTTPS (`https://your-domain.com`)
- WebSocket connections MUST use `wss://` (secure WebSocket), not `ws://`
- Cloudflare handles SSL/TLS termination
- Nginx proxies secure WebSocket to local insecure WebSocket
- Your local services don't need SSL certificates

**Example:** To connect to ROSBridge from your DEXI app:
```javascript
// ✅ Correct - uses wss:// through nginx reverse proxy
const ros = new ROSLIB.Ros({ url: 'wss://your-domain.com/rosbridge' });

// ❌ Wrong - would fail with mixed content error
const ros = new ROSLIB.Ros({ url: 'ws://your-domain.com:9090' });
```

## Troubleshooting

### Cloudflare Tunnel Issues

**Tunnel not connecting:**

If you see: `WRN No ingress rules were defined`
- Make sure you configured a Public Hostname in the Cloudflare dashboard
- Go to **Zero Trust** → **Networks** → **Tunnels** → Your Tunnel → **Public Hostname**
- Add your domain pointing to `localhost:80`

**Check tunnel is running:**
```bash
# If running manually, check the terminal output
# Look for: "Registered tunnel connection" messages

# If running as service:
sudo systemctl status cloudflared

# View logs:
sudo journalctl -u cloudflared -f
```

**Error 1033 (Argo Tunnel error):**
- Tunnel is running but Public Hostname not configured
- Configure Public Hostname in Cloudflare dashboard (see step 5 in Quick Start)
- Wait 30-60 seconds after saving for changes to propagate

**Restart tunnel:**
```bash
# If running manually: Ctrl+C and restart
cloudflared tunnel run --token <YOUR_TOKEN>

# If running as service:
sudo systemctl restart cloudflared
```

### Docker Issues

**View container logs:**
```bash
docker compose logs -f
docker compose logs nginx
docker compose logs dexi-droneblocks
```

**Restart services:**
```bash
docker compose restart
```

**Rebuild after changes:**
```bash
docker compose down
docker compose build
docker compose up -d
```

### Connection Issues

**Test local nginx:**
```bash
curl -I http://localhost
```

**Test local service directly:**
```bash
curl -I http://localhost:81
```

**Check if ports are listening:**
```bash
sudo netstat -tlnp | grep -E '(80|81|8080|1880|9090|9999)'
```

### DNS Issues

If your domain doesn't resolve:
- Verify DNS records in Cloudflare dashboard
- Check nameservers are pointing to Cloudflare
- Wait for DNS propagation (can take up to 24 hours)
- Use `dig your-domain.com` to check DNS resolution

### WebSocket Connection Errors

**Error: "Mixed Content: attempted to connect to insecure WebSocket endpoint"**

This means your app is trying to use `ws://` instead of `wss://`. Fix by:

1. Update your DEXI app code to use `wss://` for WebSocket connections
2. Use the nginx proxy paths (e.g., `wss://your-domain.com/rosbridge`)
3. Never use port numbers in the URL (e.g., ~~`:9090`~~)

**Error: "WebSocket connection failed"**

Check that:
1. The service is running: `sudo netstat -tlnp | grep 9090` (for ROSBridge)
2. Nginx is properly proxying: `docker compose logs nginx`
3. WebSocket headers are present in nginx.conf (Upgrade, Connection)
4. You're using the correct path (`/rosbridge/` with or without trailing slash)

**Verify nginx WebSocket proxy:**
```bash
# Check nginx logs when attempting WebSocket connection
docker compose logs nginx -f

# You should see WebSocket upgrade requests
```

## Maintenance

### Updating Services

```bash
# Pull latest changes
cd ~/dexi-anywhere/dexi-droneblocks
git pull

# Rebuild and restart
cd ~/dexi-anywhere
docker compose build
docker compose up -d
```

### Stopping Services

```bash
docker compose down
```

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f nginx
docker compose logs -f dexi-droneblocks
```

## Security Considerations

- The free Cloudflare Tunnel provides basic DDoS protection
- Consider adding authentication to exposed services
- Regularly update Docker images and system packages
- Review Cloudflare Zero Trust access policies
- Monitor tunnel logs for suspicious activity

## Additional Services

To enable Node-RED (currently commented out in docker-compose.yaml):

1. Uncomment the `dexi-node-red` service in `docker-compose.yaml`
2. Ensure the volume path exists: `/home/dexi/node-red-dexi/flows`
3. Restart: `docker compose up -d`

## Support

For issues specific to:
- **Cloudflare Tunnel**: [Cloudflare Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- **Docker**: [Docker Docs](https://docs.docker.com/)
- **Nginx**: [Nginx Docs](http://nginx.org/en/docs/)

## License

[Add your license here]
