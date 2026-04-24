# Ad-block DNS stack (AdGuard Home)

This stack runs network-wide DNS blocking for ads, trackers, and known malware domains.

## Why AdGuard Home instead of Pi-hole?

AdGuard Home and Pi-hole are both good. AdGuard Home is used here because:

- very easy first-run setup and filtering
- built-in DNS-over-HTTPS / DNS-over-TLS upstream support
- strong blocklist and parental control options

If you strongly prefer Pi-hole, it can be swapped later.

## Important expectation setting

DNS blockers are great, but they are **not** equal to browser content blockers such as uBlock Origin.

- DNS blocking: blocks domains before connection
- uBlock Origin: blocks network + cosmetic elements + many script-level annoyances

Best setup: run this DNS stack for all devices **and** still use uBlock Origin in browsers.

## Start

1. Copy `.env.example` to `.env`.
2. Start from `adblock-stack`:

`docker compose -f compose.yml up -d`

## First-time setup

Open setup wizard:

- `http://<server-ip>:3000`

After setup, admin UI is at:

- `http://<server-ip>:8081`

Set your router DHCP DNS to this server IP (or set DNS per device).
