# Infrastructure Stack

This stack contains core infrastructure services for monitoring, management, and backup of your homelab.

## Services

### Nginx Proxy Manager (Reverse Proxy & SSL)

- **Ports**: 80 (HTTP), 443 (HTTPS), 81 (Admin UI)
- **Purpose**: Reverse proxy with automatic SSL certificates (Let's Encrypt)
- **Access**: `http://localhost:81`
- **Default Login**: `admin@example.com` / `changeme` (change on first login)
- **Features**:
  - Proxy multiple services to single domain
  - Automatic SSL certificate generation
  - Access lists for IP filtering
  - Upstream HTTP/2 support
  - Web Socket support
  - MySQL backend for configuration persistence

### Portainer CE (Container Management)

- **Port**: 9000 (UI), 8000 (edge agent)
- **Purpose**: Docker container management UI
- **Access**: `http://localhost:9000`
- **Setup**: First login creates admin account
- **Features**:
  - Visual container management
  - Image management
  - Volume and network visualization
  - Stack templates
  - Registry management

### Uptime Kuma (Monitoring & Status)

- **Port**: 3001
- **Purpose**: Service uptime monitoring and status page
- **Access**: `http://localhost:3001`
- **Setup**: First login creates admin account
- **Features**:
  - HTTP/HTTPS monitoring
  - TCP/UDP monitoring
  - DNS monitoring
  - Custom status pages
  - Notifications (Discord, Slack, Telegram, etc.)

### Duplicati (Backup Solution)

- **Port**: 8200
- **Purpose**: Automated backup with web UI
- **Access**: `http://localhost:8200`
- **Features**:
  - Incremental backups
  - AES encryption
  - Multiple backend support (local, S3, B2, OneDrive, Google Drive, etc.)
  - Web-based configuration
  - Scheduled backups
  - Recovery point verification

## Configuration

### Environment Variables

Create a `.env` file in this directory:

```bash
TZ=America/New_York
PUID=1000
PGID=1000
```

### Backup Configuration

**To backup your stack configs:**

1. Uncomment the mount points in the `duplicati` service (or add your own)
2. Configure Duplicati at `http://localhost:8200`
3. Create a backup job pointing to `/source/` directory
4. Configure storage backend (local, cloud, etc.)

Example config mounts to add to `compose.yml`:

```yaml
volumes:
  - ./data/duplicati:/config
  - ./backups:/backups
  - ./data/nginx:/source/nginx:ro
  - ../adblock-stack/config:/source/adblock:ro
  - ../homeassistant-stack/config:/source/homeassistant:ro
  - ../plex-stack/config:/source/plex:ro
```

### Optional: Restic for Advanced Users

If you prefer Restic (lightweight CLI-based backup tool):

1. Uncomment the `restic-rest-server` service
2. Use Restic CLI to configure backups pointing to `http://localhost:8080`

```bash
restic init --repo rest:http://username:password@localhost:8080/restic
restic backup /path/to/config
```

## Starting the Stack

```bash
npm run start:infra
docker compose up -d
```

Or use the npm scripts (update package.json first):

```bash
npm run start:infra
npm run stop:infra
npm run logs:infra
```

## Accessing Services

- **Nginx Proxy Manager**: http://localhost:81 (admin UI)
- **Portainer**: http://localhost:9000
- **Uptime Kuma**: http://localhost:3001
- **Duplicati**: http://localhost:8200

## Backup Strategy

1. **Local Backups**: Use Duplicati to backup configs to `./backups/` folder
2. **Cloud Backups**: Configure Duplicati to backup to S3, B2, OneDrive, etc.
3. **Automated Schedule**: Set backups to run daily at off-peak hours
4. **Retention Policy**: Keep multiple versions (e.g., 7 days of daily, 4 weeks of weekly)

## Monitoring Setup in Uptime Kuma

1. Add monitors for each service:
   - All stacks: HTTP(S) checks to service ports
   - Databases: TCP checks to database ports
   - VPN: Monitor gluetun or VPN status

2. Create a public status page for your homelab

3. Set up notifications:
   - Discord webhook for alerts
   - Email for critical failures

## Nginx Proxy Manager Setup

### Initial Configuration

1. **First Login**:
   - URL: http://localhost:81
   - Email: `admin@example.com`
   - Password: `changeme`
   - **⚠️ IMMEDIATELY change the password!**

2. **Add Proxy Hosts** (forward domain to internal service):
   - Domain names: `example.com`, `www.example.com`
   - Scheme: `http` (for internal services)
   - Forward Hostname/IP: `192.168.x.x` or service hostname
   - Forward Port: service port (e.g., 8989 for sonarr)
   - SSL Certificate: Let's Encrypt (automatic)

3. **Enable SSL**:
   - Use Let's Encrypt certificate (free, auto-renew)
   - Force HTTPS for security
   - HTTP/2 for better performance

### Example Proxy Hosts

```
Domain: plex.example.com
  → http://plex:32400 (Plex server)

Domain: arr.example.com
  → http://192.168.1.10:8989 (Sonarr)

Domain: portainer.example.com
  → http://192.168.1.10:9000 (Portainer)
```

### Database

Nginx stores configuration in MySQL (`nginx-db` service). Configuration persists across restarts.

Database credentials (from `.env`):

- Default password: `npm-pass` (should be changed)

### Logs

```bash
npm run logs:infra:nginx
```

## Docker Socket Mount

Portainer needs access to the Docker socket to manage containers. This requires elevated permissions.

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

On systems with `podman`, you may need to adjust this.

## Troubleshooting

- **Nginx won't start**: Check ports 80, 443, 81 aren't already in use
- **Can't reach Nginx UI**: Verify container is running with `docker ps`
- **SSL certificate won't generate**: Ensure domain DNS points to your server, ports 80/443 accessible
- **Proxy not forwarding**: Verify internal service is reachable from container (use service name on homelab network)
- **Portainer won't start**: Check Docker socket permissions
- **Duplicati backup fails**: Verify source paths exist and are readable
- **Uptime Kuma can't reach services**: Services must be on the same `homelab` network
