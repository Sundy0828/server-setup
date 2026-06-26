# Minecraft Stack

Runs Minecraft servers using Docker. Supports multiple independent server instances and optional remote access via Playit.gg.

## Creating a New Server

```bash
npm run new:minecraft:paper    -- my-server      # Paper (optimized vanilla, recommended)
npm run new:minecraft:vanilla  -- my-server      # Pure vanilla survival
npm run new:minecraft:creative -- my-server      # Vanilla creative
npm run new:minecraft:curseforge -- my-server    # CurseForge modpack
npm run new:minecraft:hardcore -- my-server      # Paper hardcore (die = world over)

# Full control (any type, custom port):
npm run new:minecraft -- -Name my-server -Type vanilla-survival -Port 25566
```

This copies the right template to `minecraft-stack/servers/my-server/`, creates a `.env` with container names pre-filled, then prints the start command.

For CurseForge servers, open the `.env` and set `CF_PAGE_URL` and `CF_API_KEY` before starting.

## Templates

| Template | Server Type | Gamemode | Memory |
|---|---|---|---|
| `paper-survival` | PAPER (optimized vanilla) | survival | 6G |
| `vanilla-survival` | VANILLA | survival | 4G |
| `vanilla-creative` | VANILLA | creative / peaceful | 3G |
| `curseforge` | AUTO_CURSEFORGE | survival | 8G |
| `paper-hardcore` | PAPER | survival / hard / hardcore | 6G |

Templates live in `minecraft-stack/templates/`. You can also copy them manually if you prefer.

## Starting and Stopping Servers

```bash
cd minecraft-stack/servers/my-server

docker compose up -d                        # Start
docker compose down                         # Stop
docker compose logs -f minecraft            # Logs
docker compose --profile playit up -d      # Start with playit tunnel
```

## Configuration

Each server has a `.env` file generated from the template. Common settings:

```bash
MC_CONTAINER_NAME=minecraft-my-server
MC_PORT=25565
MC_TYPE=PAPER          # VANILLA | PAPER | FABRIC | FORGE | AUTO_CURSEFORGE
MC_VERSION=LATEST      # or pin: 1.21.4
MC_MEMORY=6G
MC_GAMEMODE=survival   # survival | creative | adventure
MC_DIFFICULTY=normal   # peaceful | easy | normal | hard
MC_MAX_PLAYERS=20
MC_MOTD=A Minecraft Server
MC_PVP=true
MC_ENABLE_WHITELIST=false
```

See the [itzg/docker-minecraft-server docs](https://github.com/itzg/docker-minecraft-server) for the full list of supported env vars.

## Directory Structure

```
minecraft-stack/
├── templates/
│   ├── paper-survival/       # Paper survival (recommended default)
│   ├── vanilla-survival/     # Pure vanilla survival
│   ├── vanilla-creative/     # Vanilla creative
│   ├── curseforge/           # CurseForge modpack
│   └── paper-hardcore/       # Paper hardcore
│
└── servers/                  # Created by npm run new:minecraft:*
    └── my-server/
        ├── compose.yml
        ├── .env
        └── data/             # Created on first run
            ├── world/
            ├── logs/
            └── server.properties
```

## Versions and Updates

With `MC_VERSION=LATEST` the container downloads the current Mojang stable release each time it starts. This is fine for casual servers. For a long-running world, pin a specific version so a restart doesn't accidentally upgrade:

```bash
MC_VERSION=1.21.4
```

**Paper lag behind vanilla releases:** Paper typically publishes builds the same day to 2 days after a Mojang release. If you need to run a brand-new version the moment it drops, use `MC_TYPE=VANILLA` — it has no middleman.

To upgrade a running server, change `MC_VERSION` in `.env` and restart. The first startup after a version bump takes longer while the world converts.

## Server Types

- **VANILLA** — Official Mojang server, no extras
- **PAPER** — Optimized vanilla, fastest for survival, no mods needed
- **FABRIC** — Lightweight mod loader (performance mods like Lithium work great here)
- **FORGE** — Heavy mod loader, needed for most large modpacks
- **AUTO_CURSEFORGE** — Automatically downloads and installs a CurseForge modpack by URL

## Port Forwarding with Playit.gg

Lets players connect without opening your router. Free tier supports one tunnel.

1. Sign up at https://playit.gg/
2. Create a tunnel in the dashboard, copy the secret key
3. Add to `.env`:
   ```bash
   PLAYIT_SECRET_KEY=your_secret_key
   PLAYIT_CONTAINER_NAME=playit-my-server
   ```
4. Start with playit enabled:
   ```bash
   docker compose --profile playit up -d
   ```
5. Get the tunnel address from the dashboard or logs:
   ```bash
   docker compose logs playit
   ```

## Backups

World data is in `servers/my-server/data/`. Point your backup solution (Duplicati in the infra-stack) at that folder.

```yaml
# In infra-stack compose.yml
- ../minecraft-stack/servers/my-server/data:/source/minecraft-my-server:ro
```

## Performance Tips

- **Memory**: 4G for 1–4 players, 6G for 5–10, 12G+ for 10+
- **Server type**: PAPER is the best vanilla-compatible choice
- **View distance**: Drop to 6–8 chunks for small servers (`view-distance` in `data/server.properties`)
- **Mods**: Use FABRIC for lighter setups, FORGE for large modpacks

## Troubleshooting

**Server won't start** — Check `docker compose logs minecraft`. Common causes: `EULA=TRUE` missing, port already in use.

**World corruption** — Stop the server, restore `data/world` from backup, restart.

**Memory issues** — Increase `MC_MEMORY` in `.env`, monitor with `docker stats`.

**Modpack won't download** — Verify `CF_PAGE_URL` is the modpack page (not a file link) and `CF_API_KEY` is valid.

## Resources

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — image docs and all env vars
- [PaperMC](https://papermc.io/) — Paper downloads and docs
- [Minecraft Wiki](https://minecraft.wiki/) — server.properties reference
- [Playit.gg](https://playit.gg/) — free tunnel service
