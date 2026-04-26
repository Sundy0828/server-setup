# Minecraft Stack

This stack runs Minecraft servers using Docker containers. It supports multiple server instances and optional Port Forwarding via Playit.gg.

## How It Works

### Server Images

**Main Image**: `itzg/minecraft-server`

This is a feature-rich Docker image maintained by the community that handles:

- Automatic server installation and setup
- Multiple server types (Vanilla, Paper, Spigot, Forge, Fabric, etc.)
- Automatic backups and log rotation
- Auto-restart on crashes
- Memory management
- World management

### Server Types Supported

The `TYPE` environment variable controls which server software runs:

- **VANILLA**: Official Minecraft server
- **PAPER**: Optimized high-performance Vanilla (recommended)
- **SPIGOT**: Plugin support
- **FABRIC**: Mod support with lightweight performance
- **FORGE**: Mod support (heavier)
- **PURPUR**: Highly customizable Vanilla
- **VELOCITY**: Proxy server
- **And more...**

### Versions and Updates

#### Why Pin Specific Versions?

The compose file uses `itzg/minecraft-server:java17-alpine` (specific Java version) instead of `:latest` because:

1. **Stability**: Pinned versions won't break if you restart a server months later
2. **Reproducibility**: Same image always produces same behavior
3. **Control**: You decide when to upgrade
4. **Long-term servers**: Minecraft worlds need consistent server software

#### Finding Latest Builds

**Official Minecraft Server Versions**:

- Check: https://www.minecraft.net/en-us/download/server
- Current stable: Usually the latest released version

**Paper (Recommended)**:

- Downloads: https://papermc.io/downloads
- Latest stable builds for each Minecraft version
- Much better performance than Vanilla

**Other Server Types**:

- **Fabric**: https://fabricmc.net/
- **Forge**: https://files.minecraftforge.net/
- **Spigot**: https://www.spigotmc.org/
- **Purpur**: https://purpurmc.org/downloads

### How Long-Term Servers Work

The Minecraft protocol is backward/forward compatible within the same major version:

```
Scenario: Start server with Minecraft 1.20.1
├─ Server runs fine on players' 1.20.1 clients
├─ Server software gets updates for bugfixes (1.20.1-paper-X → 1.20.1-paper-Y)
│  └─ Update by changing the `VERSION` environment variable and restarting
├─ Several months pass...
├─ You restart the server again later
│  └─ Same compose.yml, same server image
│  └─ Server starts with same configuration
│  └─ Existing world loads perfectly
│
└─ To upgrade to Minecraft 1.21: Change VERSION=1.21 in .env and restart
   └─ First startup takes longer as it converts the world
   └─ World is now ready for 1.21
```

## Server Directory Structure

```
minecraft-stack/
├── servers/
│   ├── server-test/          # Example test server
│   │   ├── compose.yml
│   │   ├── README.md
│   │   ├── .env              # Server-specific config
│   │   └── data/             # Server data (created on first run)
│   │       ├── world/        # World files
│   │       ├── logs/         # Server logs
│   │       ├── backups/      # Auto backups
│   │       ├── server.properties
│   │       └── ...
│   └── server-survival/      # Your survival server (add as needed)
│       ├── compose.yml
│       ├── .env
│       └── data/
│
└── templates/
    └── server-template/      # Template for new servers
        ├── compose.yml
        └── README.md
```

## Configuration

### Per-Server Configuration

Each server has its own `.env` file:

```bash
# Basic
MC_CONTAINER_NAME=minecraft-test
MC_PORT=25565
MC_TYPE=PAPER              # Server type
MC_VERSION=LATEST          # Server version
MC_MEMORY=6G               # RAM allocation
MC_ENABLE_WHITELIST=false

# Optional
TZ=America/New_York
EULA=TRUE                  # Must be TRUE

# Playit.gg (for port forwarding)
PLAYIT_CONTAINER_NAME=playit-minecraft-test
PLAYIT_SECRET_KEY=your_secret_key_here
CF_PAGE_URL=https://your-cloudflare-page.com
CF_API_KEY=your_cloudflare_api_key
```

### Properties File

Server configuration (like difficulty, mode, etc.) is in:

```
./data/server.properties
```

Edit this file to:

- Change game mode (survival, creative, adventure)
- Set difficulty level
- Enable PvP
- Configure spawn protection
- And more...

See: https://minecraft.wiki/w/Server.properties

## Managing Servers

### Creating a New Server

1. **Copy the template**:

   ```bash
   cp -r minecraft-stack/templates/server-template minecraft-stack/servers/server-survival
   ```

2. **Update `.env`**:

   ```bash
   MC_CONTAINER_NAME=minecraft-survival
   MC_PORT=25566         # Different port than test
   MC_TYPE=PAPER
   MC_VERSION=LATEST
   ```

3. **Start the server**:
   ```bash
   cd minecraft-stack/servers/server-survival
   docker compose up -d
   ```

### Starting/Stopping Servers

```bash
# Using npm (from root)
npm run start:minecraft -- server-test
npm run stop:minecraft -- server-test
npm run logs:minecraft -- server-test

# Or directly
cd minecraft-stack/servers/server-test
docker compose up -d    # Start
docker compose down      # Stop
docker compose logs -f   # View logs
```

### Updating Server Version

Edit the server's `.env`:

```bash
# Old
MC_VERSION=1.20.1

# New
MC_VERSION=1.20.4
```

Restart the server:

```bash
docker compose restart minecraft
```

The server will:

1. Download the new version
2. Update libraries if needed
3. Start with the new version
4. Keep all worlds and player data

### Viewing Server Logs

```bash
# Using npm
npm run logs:minecraft -- server-test

# Or directly
cd minecraft-stack/servers/server-test
docker compose logs -f minecraft
```

## Port Forwarding with Playit.gg

The stack includes optional Playit.gg support for playing without port forwarding:

1. **Sign up**: https://playit.gg/
2. **Get secret key** from dashboard
3. **Add to `.env`**:
   ```bash
   PLAYIT_SECRET_KEY=your_secret_key
   ```
4. **Start Playit**:
   ```bash
   docker compose --profile playit up -d
   ```
5. **Get URL**: Check Playit dashboard or logs:
   ```bash
   docker compose logs playit
   ```

## Backups

Automatic backups happen in the container. To backup world data:

```bash
# Manual backup
cd minecraft-stack/servers/server-test
cp -r data/world ../../../backups/server-test-$(date +%s)
```

Or configure the infra-stack backup service to backup these directories:

```yaml
# In infra-stack compose.yml
- ../minecraft-stack/servers/server-test/data:/source/minecraft-test:ro
```

## Performance Tips

1. **Memory**: Allocate based on player count
   - 2-4 players: 4GB
   - 5-10 players: 6-8GB
   - 10+ players: 12GB+

2. **Server Type**: Use PAPER for best vanilla performance

3. **Mods**: Use Fabric for lighter mod setups, Forge for more mods

4. **View Distance**: Balance performance vs. visual range
   - Default: 10 chunks
   - Recommendation: 6-8 for small servers

5. **Difficulty**: Higher difficulty = more computation

## Troubleshooting

**Server won't start**:

- Check logs: `docker compose logs minecraft`
- Verify EULA=TRUE in .env
- Check port isn't already in use

**World corruption**:

- Backups are in `data/backups/`
- Stop server, restore from backup, restart

**Memory issues**:

- Increase `MC_MEMORY` in .env
- Monitor with: `docker stats`

**Mods won't load**:

- Ensure server type matches (FABRIC for Fabric mods, FORGE for Forge, etc.)
- Check mod versions match server version

## Resources

- **Official Docs**: https://minecraft.wiki/
- **Paper Project**: https://papermc.io/
- **Server Image**: https://github.com/itzg/docker-minecraft-server
- **Playit.gg**: https://playit.gg/
