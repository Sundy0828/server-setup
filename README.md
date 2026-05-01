# Home Server Setup

This setup is split into independent stacks:

- `plex-stack` for Plex + Arr + Overseerr + Tailscale + download stack
- `minecraft-stack` for one-at-a-time Minecraft with copyable server templates
- `homeassistant-stack` for Home Assistant
- `adblock-stack` for network-wide DNS blocking (AdGuard Home)
- `nginx-stack` for NGINX Proxy Manager (reverse proxy)

## Quick Start with npm scripts

**Start entire ecosystem:**

```bash
npm run setup
npm run start:all
```

**Start individual stacks:**

```bash
npm run start:nginx
npm run start:adblock
npm run start:homeassistant
npm run start:plex
npm run start:plex:usenet     # With SABnzbd (Usenet)
```

**Stop stacks:**

```bash
npm run stop:all
npm run stop:plex
npm run stop:homeassistant
```

**View logs:**

```bash
npm run logs:plex
npm run logs:plex:sonarr
npm run logs:plex:radarr
npm run logs:plex:qbittorrent
npm run logs:adblock
npm run logs:homeassistant
npm run logs:nginx
```

**Minecraft servers (manual mode):**

Each server runs independently. To start a server:

```bash
cd minecraft-stack/servers/<server-name>
docker compose up -d
docker compose --profile playit up -d    # With playit.gg sidecar
```

## 1) Plex stack setup

1. Go to `plex-stack`.
2. Copy `.env.example` to `.env` and fill in secrets.
3. Update `config/tailscale-overseerr/serve.json` so host matches your tailnet DNS name.
4. Create directories if needed:
   - `plex-stack/config/*`
   - `plex-stack/data/downloads`
   - `plex-stack/data/media`

## 2) Start plex stack

From `plex-stack`:

`docker compose -f compose.yml up -d`

### Service URLs (local LAN)

- Plex: `http://localhost:32400/web`
- Sonarr: `http://localhost:8989`
- Radarr: `http://localhost:7878`
- Lidarr: `http://localhost:8686`
- Readarr: `http://localhost:8787`
- Prowlarr: `http://localhost:9696`
- Bazarr: `http://localhost:6767`
- qBittorrent: `http://localhost:8080`
- SABnzbd (optional): `http://localhost:8085`

Overseerr is intentionally not exposed on LAN ports; access it via Tailscale HTTPS.

Optional Usenet downloader:

- SABnzbd is included behind the `usenet` profile and is off by default.
- Start with SABnzbd enabled:
  - `docker compose --profile usenet -f compose.yml up -d`

## 3) Start Minecraft stack (copy/rename template)

### Create server

Template folder:

`minecraft-stack/templates/server-template`

Create each world/server instance:

1. Copy `minecraft-stack/templates/server-template` to `minecraft-stack/servers/<server-name>`.
2. Copy `.env.example` to `.env` inside that new server folder.
3. Edit `.env`:
   - `MC_CONTAINER_NAME` (unique name per server)
   - `MC_PORT` (use `25565` for the active one)
   - `MC_TYPE=PAPER` for vanilla-ish, or `MC_TYPE=AUTO_CURSEFORGE` for modpacks
   - `CF_PAGE_URL` for modpacks (CurseForge URL)
   - Optional playit.gg:
     - `PLAYIT_SECRET_KEY` from playit.gg dashboard
4. Start from that server folder:
   - `docker compose up -d`
   - With playit.gg sidecar:
     - `docker compose --profile playit up -d`
5. Switch server:
   - Stop current server: `docker compose down`
   - Start another server folder (usually also on `MC_PORT=25565`)

Each server folder keeps its own world/config data in `servers/<server-name>/data`.

### playit.gg architecture recommendation

- For your current workflow (one active Minecraft instance at a time), use one playit sidecar in the active server folder.
- Running one playit per instance is fine if only one is up at a time.
- If you later run multiple Minecraft instances simultaneously, move to one dedicated global playit stack and manage multiple tunnels from that agent.

### View Logs

#### Live logs (recommended)

```bash
docker logs -f <container-name>
```

Example:

```bash
docker logs -f minecraft-test
```

Logs with timestamps

```bash
docker logs -f -t minecraft-test
```

Recent logs only

```bash
docker logs --tail 200 minecraft-test
```

#### File-based logs (most detailed)

Each server writes logs here:

```bash
servers/<server-name>/data/logs/latest.log
```

Follow live:

```bash
tail -f servers/<server-name>/data/logs/latest.log
```

### Troubleshooting

Paper version support is tracked here:

https://papermc.io/downloads/paper

Use this to:

- verify supported Minecraft versions
- choose valid MC_VERSION values
- avoid using unsupported client/server combinations

> If a version is not listed, Paper does not support it yet.

## 4) Start Home Assistant stack

From `homeassistant-stack`:

1. Copy `.env.example` to `.env`.
2. Start:
   - `docker compose -f compose.yml up -d`
3. Open:
   - `http://localhost:8123`

## 5) Start ad-block DNS stack

From `adblock-stack`:

1. Copy `.env.example` to `.env`.
2. Start:
   - `docker compose -f compose.yml up -d`
3. First-run setup wizard:
   - `http://localhost:3002`
4. Admin UI (after setup):
   - `http://localhost:8081`

Set router/device DNS to your server IP to apply blocking network-wide.

### Troubleshooting

setup Adguard to use your machine as the dns

> This will make it so you won't have wifi unless adguard is running

1. Windows + R, type ncpa.cpl, and press enter.
2. right click on wifi and go to properties
3. double click Internet Protocol Version 4 (IPv4)
4. switch from automatic to Use the following DNS server addresses and set the ip to computers IP

may need to run these after updating

```bash
ipconfig /release
ipconfig /renew
ipconfig /flushdns
netsh int ip reset
```

Note:

> switch back to automatic if you want to use wifi without docker running

Setup TP-Link

1. Go to 192.168.0.1
2. sign in and go to Advanced > Network > DHCP Server
3. set primary to IP of machine hosting adgaurd

### AdGuard Home vs uBlock Origin / Brave

- DNS blocking is excellent for network-wide domain blocking.
- Browser blockers (especially uBlock Origin) still provide stronger in-page/script/cosmetic blocking.
- Best result: use this DNS stack + keep uBlock Origin in browser.

## 6) Recommended app wiring order

1. Configure qBittorrent download categories/paths first.
2. Add indexers in Prowlarr.
3. Sync Prowlarr apps to Sonarr/Radarr/Lidarr/Readarr.
4. In each Arr app, use root folders under `/data/media/...` and downloads under `/data/downloads`.
5. Connect Overseerr to Plex, Sonarr, and Radarr.

## 7) TRaSH guides (highly recommended)

Use TRaSH guides to import quality profiles and custom formats:

- [TRaSH Guides](https://trash-guides.info/)

Typical order:

1. Import quality profiles and custom formats to Sonarr/Radarr.
2. Import naming and release profile recommendations.
3. Revisit score thresholds after a few days of downloads.

## 8) Security notes

- Do not expose Arr/qBittorrent ports directly to the internet.
- Keep Overseerr private through Tailscale (no router port-forward needed).
- Rotate `TS_AUTHKEY` and VPN keys periodically.
- Keep Docker images updated (`docker compose pull` then `up -d`).
