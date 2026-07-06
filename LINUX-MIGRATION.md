# Windows → Debian 13 Migration Guide

This repo was previously running on Windows 11. This document covers everything needed to get all stacks running on Debian 13.

## What's in This Repo

| Stack | Services |
|-------|----------|
| `infra-stack` | NGINX Proxy Manager, Authelia (SSO), Homepage, Uptime Kuma, Duplicati, Redis |
| `plex-stack` | Plex, Sonarr, Radarr, Lidarr, Readarr, Prowlarr, Bazarr, qBittorrent (via Mullvad VPN), Audiobookshelf, Overseerr, Tailscale sidecars |
| `adblock-stack` | AdGuard Home (DNS) |
| `homeassistant-stack` | Home Assistant |
| `minecraft-stack` | Minecraft servers (PaperMC) |

All stacks use Docker Compose. There is a shared Docker network called `homelab`.

---

## Step 1 — Install Software

```bash
# Docker Engine (not Docker Desktop)
apt install docker.io docker-compose-plugin

# Node.js (optional — only needed if you want to use npm run scripts)
apt install nodejs npm

# Add your user to the docker group so you don't need sudo every time
usermod -aG docker $USER
newgrp docker
```

---

## Step 2 — Copy This Repo

Copy the entire `server-setup/` folder from the external drive to the Linux machine, e.g.:

```bash
cp -r /media/external/server-setup ~/server-setup
cd ~/server-setup
```

---

## Step 3 — Fix Port 53 Conflict (AdGuard)

Debian runs `systemd-resolved` which listens on port 53 by default. AdGuard Home will fail to start until you disable it.

```bash
systemctl disable --now systemd-resolved

# Point DNS at something temporarily until AdGuard is running
echo "nameserver 8.8.8.8" | tee /etc/resolv.conf
```

---

## Step 4 — Fix Hard-coded Windows Paths in plex-stack

Open `plex-stack/compose.yml` and find these Windows drive letter paths:

```yaml
- D:/Audiobooks:/data/audiobooks
- D:/Music/Media.localized/Music:/data/music
- D:/Audiobooks:/audiobooks
```

Replace `D:/Audiobooks` and `D:/Music/Media.localized/Music` with wherever you store those folders on the Linux machine, e.g.:

```yaml
- /mnt/media/audiobooks:/data/audiobooks
- /mnt/media/music:/data/music
- /mnt/media/audiobooks:/audiobooks
```

If those folders are on an external drive, make sure it's mounted first (e.g. via `/etc/fstab`).

---

## Step 5 — Update Host IP (if it changed)

Check what LAN IP the Debian server got:

```bash
ip addr show
```

If it's different from `192.168.0.54`, update it in `infra-stack/.env`:

```
HOMELAB_HOST_IP=<new-ip>
```

Also update the hardcoded default in `scripts/homelab-services.ps1` if you plan to convert those scripts later.

**Recommended:** Set a static IP on the server so it never drifts. Either configure it in `/etc/network/interfaces` or via your router's DHCP reservations.

---

## Step 6 — Check PUID/PGID

The `.env` files use `PUID=1000` and `PGID=1000`. The first user created during Debian install is UID/GID 1000 by default. Confirm this matches:

```bash
id
# Should show: uid=1000(...) gid=1000(...)
```

If different, update `PUID` and `PGID` in `plex-stack/.env` to match your actual UID/GID.

---

## Step 7 — Create the Docker Network

```bash
docker network create homelab
```

---

## Step 8 — Start All Stacks

The `package.json` npm scripts invoke PowerShell and won't work on Linux. Run Docker Compose directly:

```bash
cd ~/server-setup

cd infra-stack && docker compose up -d && cd ..
cd adblock-stack && docker compose up -d && cd ..
cd plex-stack && docker compose up -d && cd ..
cd homeassistant-stack && docker compose up -d && cd ..
```

For Minecraft servers (if needed):

```bash
cd minecraft-stack/servers/survival-world && docker compose up -d && cd ../../..
```

---

## Step 9 — Redo One-Time Setup via Web UIs

The PowerShell setup scripts (`setup-nginx-authelia.ps1`, `setup-ssl-cert.ps1`, `setup-adguard-dns.ps1`) were one-time configuration steps that called the APIs of running containers. On Linux, redo these through the web UIs:

### AdGuard DNS Rewrites (port 8081)

Go to `http://<server-ip>:8081` → Filters → DNS Rewrites.

Add an A record for each service pointing to the server's LAN IP, e.g.:

| Domain | Answer |
|--------|--------|
| `sonarr.home.lab` | `192.168.0.54` |
| `radarr.home.lab` | `192.168.0.54` |
| `plex.home.lab` | `192.168.0.54` |
| *(etc for all services)* | |

### NGINX Proxy Manager — Proxy Hosts (port 81)

Go to `http://<server-ip>:81` → Proxy Hosts.

Re-create the proxy host entries for each service. Each one maps `<service>.home.lab` → `http://<container-name>:<port>`. The container names and ports are defined in each `compose.yml`.

### SSL Certificate (HTTPS)

Since `*.home.lab` is a local domain, Let's Encrypt cannot issue a cert for it via normal HTTP verification. In NGINX Proxy Manager:

- Go to SSL Certificates → Add SSL Certificate → Custom
- Either generate a new self-signed wildcard cert for `*.home.lab`, or if you previously had a local CA set up, re-import those cert files

Once the cert exists, edit each proxy host and assign the wildcard cert under the SSL tab.

### Authelia Forward Auth

When creating proxy hosts in NGINX Proxy Manager, re-add the Authelia forward auth configuration under Advanced for each protected service. The Authelia container is on the `homelab` network accessible at `http://authelia:9091`.

---

## Step 10 — Configure *arr Apps

The `plex-stack/run-arr-setup.ps1` script automates connecting Sonarr/Radarr/etc. to qBittorrent and setting root folders. It runs a Docker Alpine container with a Bash script, so it can be converted or you can configure each *arr app manually through their web UIs at the ports below.

| App | Port |
|-----|------|
| Sonarr | 8989 |
| Radarr | 7878 |
| Lidarr | 8686 |
| Readarr | 8787 |
| Prowlarr | 9696 |
| Bazarr | 6767 |

---

## What Does NOT Need to Change

Everything below carries over from the Windows setup unchanged:

- All `.env` files (except `HOMELAB_HOST_IP` if the IP changed)
- All `config/` and `data/` directories — copy as-is
- Authelia config, `users_database.yml`, and all secrets
- Gluetun / Mullvad WireGuard keys
- Tailscale auth keys
- Plex token and claim
- Minecraft server data and configs

---

## Troubleshooting

**AdGuard won't start** — Port 53 still in use. Re-run the `systemd-resolved` disable steps above and confirm with `ss -tulpn | grep :53`.

**Containers can't reach each other** — Confirm the `homelab` network exists: `docker network ls`. All stacks declare it as an external network so it must exist before any stack starts.

**Permission errors on volumes** — Run `ls -la` on the `config/` and `data/` directories. The owning UID should match your `PUID` value. Fix with `chown -R 1000:1000 ./config ./data` inside each stack directory.

**Plex hardware transcoding** — If you were using GPU transcoding on Windows, you may need to pass through the GPU device in `plex-stack/compose.yml` using the `devices:` key for your GPU type (Intel/AMD/Nvidia each differ).

**NGINX Proxy Manager's MySQL container won't start / crash-loops with "Different lower_case_table_names settings"** — The `nginx-db` data directory was originally initialized on a case-insensitive filesystem (Windows/Docker Desktop bind mount), which sets `lower_case_table_names=2` in MySQL's data dictionary. Linux ext4 is case-sensitive, and MySQL 8 refuses to honor `lower_case_table_names=2` on a genuinely case-sensitive filesystem — it isn't just a config flag you can override. There's no clean in-place fix; either export/reimport the data via a temporary case-insensitive loop-mounted filesystem, or wipe `infra-stack/data/nginx/mysql` and let it reinitialize empty (then redo proxy hosts/SSL certs through the NPM web UI at port 81, same as Step 9 above).

**qBittorrent port-forward sidecar crash-loops** — Mullvad discontinued port forwarding for torrenting in 2023. The `qbittorrent-port-forward` service in `plex-stack/compose.yml` can never succeed against Mullvad and is commented out by default. Re-enable it only if you switch to a VPN provider that still supports port forwarding.

**CRLF line endings / BOM characters** — If this repo is ever copied back and forth from a Windows machine, `.sh` files can pick up CRLF line endings (breaks the shebang line, `bad interpreter` errors) and `.env` files can pick up a UTF-8 BOM. A `.gitattributes` file now normalizes line endings on checkout, but files copied outside of git (e.g. via a USB drive) can still reintroduce this — run `file <path>` to check, and `sed -i 's/\r$//' <path>` to strip CRLF.

**Sudo and this assistant** — Claude Code's Bash tool runs in its own session, so `sudo -v` run in your interactive terminal does not carry over (sudo's credential cache is per-TTY). If Claude needs sudo for a task, the simplest fix is a scoped, temporary rule in `/etc/sudoers.d/` (e.g. `jerrod ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/sbin/usermod, /usr/bin/systemctl, /usr/bin/docker`), removed again once the task is done.
