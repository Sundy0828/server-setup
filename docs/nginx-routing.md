# NGINX Routing

## Purpose

Central routing layer for all homelab services using NGINX Proxy Manager.

NGINX Proxy Manager handles:

- Local domain routing
- SSL (future)
- External access (optional)

---

## Base Domain Strategy

Using `.home.lab` domains for internal access:

| Domain               | Service       | Container Port  |
| -------------------- | ------------- | --------------- |
| adguard.home.lab     | adguardhome   | 3002            |
| home.home.lab        | homeassistant | 8123            |
| plex.home.lab        | plex          | 32400           |
| sonarr.home.lab      | sonarr        | 8989            |
| radarr.home.lab      | radarr        | 7878            |
| lidarr.home.lab      | lidarr        | 8686            |
| bazarr.home.lab      | bazarr        | 6767            |
| prowlarr.home.lab    | prowlarr      | 9696            |
| qbittorrent.home.lab | qbittorrent   | 8080            |
| overseerr.home.lab   | overseerr     | 5055 (internal) |
| minecraft.home.lab   | minecraft     | 25565 (tcp)     |
| dashboard.home.lab   | homepage      | 3000            |

---

## Notes

- All services must be on the shared `homelab` docker network
- NGINX Proxy Manager connects to services via container name
- Example:
  - `http://sonarr:8989`
  - `http://radarr:7878`

---

## Access Rules

- Internal only:
  - adguard.home.lab
  - home.home.lab

- Internal + remote (via Tailscale or future exposure):
  - overseerr.home.lab
  - plex.home.lab

---

## Future

- Add SSL via NGINX Proxy Manager
- Possibly move from `.home.lab` to a real domain
- Add authentication layer for sensitive services
