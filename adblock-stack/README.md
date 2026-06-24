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

Open setup wizard (first run only):

- `http://localhost:3002`

After setup, admin UI and API are at:

- `http://localhost:8081`

## Making it network-wide

AdGuard only blocks ads and resolves `.home.lab` domains for devices that use it as their DNS server. Configure the router so every device gets it automatically — no changes needed on individual phones, tablets, or laptops.

### 1. Open Windows Firewall for DNS (run once as Administrator)

Right-click PowerShell → Run as Administrator:

```powershell
New-NetFirewallRule -DisplayName "AdGuard DNS UDP" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow
New-NetFirewallRule -DisplayName "AdGuard DNS TCP" -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow
```

Verify:

```powershell
Get-NetFirewallRule -DisplayName "AdGuard DNS*" | Select-Object DisplayName, Enabled, Direction, Action
```

### 2. Configure your router's DHCP DNS

Log into your router admin page and find **DHCP settings**:

- **Primary DNS:** `192.168.0.54`
- **Secondary DNS:** leave blank

Leaving secondary DNS blank is intentional. If you set it to `8.8.8.8`, Android devices on "Automatic" Private DNS will detect that Google supports encrypted DNS and route all queries there instead — bypassing AdGuard entirely and breaking `.home.lab` resolution.

If AdGuard goes down, DNS stops working for the network. For a homelab this is an acceptable trade-off — AdGuard itself forwards to Cloudflare/Quad9 for internet domains, so internet works as long as AdGuard is running.

## Verifying it works

- Open `http://192.168.0.54:8081` → **Query Log** and browse on any device — queries should appear in real time
- Visit `http://doubleclick.net` from any device — AdGuard should block it
- `.home.lab` domains should resolve on any device connected to your WiFi

## Known limitation: client IPs show as 172.18.0.1

All DNS clients appear as `172.18.0.1` in AdGuard's dashboard and query log instead of their real IPs. This is a Docker-on-Windows limitation — Windows Docker Desktop NATs all published port traffic through the bridge gateway, so AdGuard never sees the original client IP. Ad blocking and DNS rewrites work correctly; you just can't see per-device stats or apply per-client filtering rules. Fixing this would require running AdGuard directly on the host outside of Docker.
