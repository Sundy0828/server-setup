# Homelab Setup & Management

## Initial Setup

Before starting your homelab, run the setup command which will:

1. Create the `homelab` Docker network
2. Copy Homepage configuration from the example directory

```bash
npm run setup
```

Or with force flag to overwrite existing Homepage config:

```bash
npm run setup:force
```

## Usage

### Starting Services

```bash
# Start all services (creates network automatically)
npm run start:all

# Start individual stacks
npm run start:adblock
npm run start:homeassistant
npm run start:plex
npm run start:infra

# Start Plex with optional usenet profile
npm run start:plex:usenet
```

### Stopping Services

```bash
# Stop all services
npm run stop:all

# Stop individual stacks
npm run stop:adblock
npm run stop:homeassistant
npm run stop:plex
npm run stop:infra
```

### Viewing Logs

```bash
# View logs for all services (help text)
npm run logs:all

# View logs for specific stack
npm run logs:adblock
npm run logs:homeassistant
npm run logs:plex
npm run logs:infra

# View logs for specific service
npm run logs:plex:sonarr
npm run logs:plex:radarr
npm run logs:plex:qbittorrent
npm run logs:infra:nginx
npm run logs:infra:duplicati
```

### Docker Network

The `homelab` network is automatically created when you run `npm run start:all` or manually with:

```bash
npm run network:create
```

All services connect to this network for inter-service communication.

## Homepage Configuration

Homepage configuration files are stored in `infra-stack\yaml-config\homepage/` which is tracked in git:

- `services.yaml` - Service cards and links
- `settings.yaml` - Dashboard appearance
- `widgets.yaml` - System monitoring widgets
- `bookmarks.yaml` - External bookmarks

When you run `npm run setup`, these files are copied to `infra-stack/config/homepage/` where the Homepage container mounts them.

**Note**: The `config/` directories are gitignored (contain runtime data), but `infra-stack\yaml-config\homepage/` is tracked.

## Environment Configuration

1. Copy `.env.example` to `.env` in each stack directory
2. Fill in required values:
   - API keys (Sonarr, Radarr, etc.)
   - VPN credentials
   - Domain/host settings
   - etc.

## First Time Setup Checklist

- [ ] Run `npm run setup`
- [ ] Copy `.env.example` → `.env` in each stack
- [ ] Fill in required environment variables
- [ ] Run `npm run start:all`
- [ ] Access Homepage at `http://localhost:3000`
- [ ] Configure Nginx PM at `http://localhost:81`
- [ ] Access other services as needed

## Service Ports

- **Homepage**: 3000
- **Nginx Proxy Manager**: 81 (admin), 80/443 (proxy)
- **Portainer**: 9000
- **Uptime Kuma**: 3001
- **Duplicati**: 8200
- **AdGuard Home**: 3002 (admin), 53 (DNS)
- **Home Assistant**: 8123
- **Plex**: 32400
- **Sonarr**: 8989
- **Radarr**: 7878
- **Lidarr**: 8686
- **Readarr**: 8787
- **Prowlarr**: 9696
- **Bazarr**: 6767
- **qBittorrent**: 8080
- **Overseerr**: Accessible via Tailscale (not exposed locally)
