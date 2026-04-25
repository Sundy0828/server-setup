# NGINX Routing

## Purpose

Central routing layer for all homelab services using NGINX Proxy Manager.

NGINX Proxy Manager handles:

- Local domain routing
- SSL (future)
- External access (optional)

---

## Base Domain Strategy

Using `.local` domains for internal access:

| Domain            | Service       | Container Port  |
| ----------------- | ------------- | --------------- |
| adguard.local     | adguardhome   | 3000            |
| home.local        | homeassistant | 8123            |
| plex.local        | plex          | 32400           |
| sonarr.local      | sonarr        | 8989            |
| radarr.local      | radarr        | 7878            |
| lidarr.local      | lidarr        | 8686            |
| bazarr.local      | bazarr        | 6767            |
| prowlarr.local    | prowlarr      | 9696            |
| qbittorrent.local | qbittorrent   | 8080            |
| overseerr.local   | overseerr     | 5055 (internal) |
| minecraft.local   | minecraft     | 25565 (tcp)     |

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
  - adguard.local
  - home.local

- Internal + remote (via Tailscale or future exposure):
  - overseerr.local
  - plex.local

---

## Future

- Add SSL via NGINX Proxy Manager
- Possibly move from `.local` to a real domain
- Add authentication layer for sensitive services
