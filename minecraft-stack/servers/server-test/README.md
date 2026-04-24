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
