# Port Configuration Generator

Automatically extracts and validates port configurations from all Docker Compose files in your homelab setup.

## Usage

```bash
npm run ports:report
```

## What It Does

The script scans all your Docker Compose files and generates:

1. **Complete Port Mapping Report** - Shows all exposed ports across your entire stack
2. **NGINX Proxy Manager Configuration** - Recommended settings for each service with:
   - Correct container ports for internal Docker networking (not host ports)
   - Domain names (\*.home.lab)
   - WebSocket requirements
   - Protocol information
3. **AdGuard DNS Rewrites** - Complete table of DNS rewrite rules needed
4. **Validation** - Checks your existing NGINX configuration

## Key Points

⚠️ **Docker Internal Networking**: When configuring NGINX Proxy Manager, always use **container ports** (the right side of the mapping), not host ports. For example:

- AdGuard: Host `3002` → Container `3000` → Use `3000` in NGINX

✅ **Services Without Exposed Ports**: qBittorrent, Overseerr, and Minecraft are accessible via the Docker network but don't expose ports. NGINX can still proxy to them because they're on the same Docker network.

## Example Output

```
🌐 NGINX PROXY MANAGER CONFIGURATION

✅ adguard.home.lab
   Forward Host: adguardhome
   Forward Port: 3000
   (Web UI on port 3000, not DNS port 53)

✅ plex.home.lab
   Forward Host: plex
   Forward Port: 32400

⚠️  qbittorrent.home.lab
   Forward Host: qbittorrent
   Forward Port: 8080
   (Service has no exposed ports - uses internal Docker network)
```

## Files

- `scripts/generate-ports.js` - The port configuration generator
- `package.json` - Updated with the `ports:report` npm script and `js-yaml` dependency

## Automation

This script is automatically generated from your Docker Compose files. To update it:

1. Modify your `compose.yml` files
2. Run `npm run ports:report` to see the updated configuration
3. Apply changes to NGINX Proxy Manager as needed
