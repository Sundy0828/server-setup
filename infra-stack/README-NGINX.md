# NGINX Proxy Manager Stack

Central reverse proxy for homelab services.

## Quick Start

```bash
docker-compose up -d
```

Access admin UI: `http://localhost:81`

- Default credentials: `admin@example.com` / `changeme`

## Setup: Routes in NGINX Proxy Manager

Access the admin UI and add these proxy hosts (Proxy Hosts menu):

### Ad Blocking

- **Domain Names**: `adguard.home.lab`
- **Forward Host**: `adguardhome`
- **Forward Port**: `3000`
- **Cache Assets**: OFF

### Home Automation

- **Domain Names**: `home.home.lab`
- **Forward Host**: `homeassistant`
- **Forward Port**: `8123`
- **WebSocket Support**: ON (if needed)
- **Cache Assets**: OFF

### Media - Plex

- **Domain Names**: `plex.home.lab`
- **Forward Host**: `plex`
- **Forward Port**: `32400`
- **Cache Assets**: OFF

### Media - Sonarr

- **Domain Names**: `sonarr.home.lab`
- **Forward Host**: `sonarr`
- **Forward Port**: `8989`
- **Cache Assets**: OFF

### Media - Radarr

- **Domain Names**: `radarr.home.lab`
- **Forward Host**: `radarr`
- **Forward Port**: `7878`
- **Cache Assets**: OFF

### Media - Lidarr

- **Domain Names**: `lidarr.home.lab`
- **Forward Host**: `lidarr`
- **Forward Port**: `8686`
- **Cache Assets**: OFF

### Media - Bazarr

- **Domain Names**: `bazarr.home.lab`
- **Forward Host**: `bazarr`
- **Forward Port**: `6767`
- **Cache Assets**: OFF

### Media - Prowlarr

- **Domain Names**: `prowlarr.home.lab`
- **Forward Host**: `prowlarr`
- **Forward Port**: `9696`
- **Cache Assets**: OFF

### Media - qBittorrent

- **Domain Names**: `qbittorrent.home.lab`
- **Forward Host**: `qbittorrent`
- **Forward Port**: `8080`
- **Cache Assets**: OFF

### Media - Overseerr

- **Domain Names**: `overseerr.home.lab`
- **Forward Host**: `overseerr`
- **Forward Port**: `5055`
- **Cache Assets**: OFF

### Minecraft

- **Domain Names**: `minecraft.home.lab`
- **Forward Host**: `minecraft`
- **Forward Port**: `25565`
- **Protocol**: TCP (not HTTP)
- **Cache Assets**: OFF

---

## Setup: AdGuard Home DNS Rewrites

Access AdGuard Home admin UI: `http://adguard.home.lab:3000` (or direct IP:3000)

Navigate to: **Filters** → **DNS rewrites**

Add these rewrite rules:

| Domain               | Answer                     |
| -------------------- | -------------------------- |
| adguard.home.lab     | nginx-pm (or container IP) |
| home.home.lab        | nginx-pm (or container IP) |
| plex.home.lab        | nginx-pm (or container IP) |
| sonarr.home.lab      | nginx-pm (or container IP) |
| radarr.home.lab      | nginx-pm (or container IP) |
| lidarr.home.lab      | nginx-pm (or container IP) |
| bazarr.home.lab      | nginx-pm (or container IP) |
| prowlarr.home.lab    | nginx-pm (or container IP) |
| qbittorrent.home.lab | nginx-pm (or container IP) |
| overseerr.home.lab   | nginx-pm (or container IP) |
| minecraft.home.lab   | nginx-pm (or container IP) |

**Or**, if you prefer to use the NGINX container IP directly:

```bash
docker inspect nginx-pm | grep '"IPAddress"'
```

Use that IP for all rewrite rules above (e.g., `172.21.0.3`).

---

## Environment Variables

Create a `.env` file in this directory:

```
MYSQL_ROOT_PASSWORD=your-secure-root-password
MYSQL_PASSWORD=your-secure-npm-password
```

---

## Notes

- All services connect via the `homelab` docker network
- NGINX Proxy Manager communicates with services using container names
- DNS rewrites in AdGuard route `.home.lab` domains to NGINX Proxy Manager
- Default admin credentials should be changed immediately after first login
