# Minecraft Server Template

Use this folder as a copyable template for each world/server.

## Create a new server instance

1. Copy this folder to `minecraft-stack/servers/<server-name>`.
2. Copy `.env.example` to `.env`.
3. Edit `.env` values (name, type, memory, optional modpack).
4. Start from that server folder:

`docker compose up -d`

## Examples

- Vanilla-ish optimized: `MC_TYPE=PAPER`
- Modpack: `MC_TYPE=AUTO_CURSEFORGE` and set `CF_PAGE_URL`

## Optional: playit.gg tunnel

This template includes an optional `playit` service to expose Minecraft safely without router port forwarding.

1. Put your playit agent secret in `.env`:
   - `PLAYIT_SECRET_KEY=...`
2. Start with playit enabled:
   - `docker compose --profile playit up -d`

### Per-server vs one global playit

- If you only run one Minecraft instance at a time, this per-server profile is easiest and clean.
- If you run multiple Minecraft instances at once, a separate global playit stack is better so one agent can manage multiple tunnels.
