# Shared service catalog for NPM proxy hosts and AdGuard DNS rewrites.
# Dot-source from setup scripts: . "$PSScriptRoot/homelab-services.ps1"

$script:HomelabServices = @(
    @{ name = "authelia";     host = "authelia";      port = 9091;  ws = $false; skipAuth = $true;  dns = $true }
    @{ name = "dashboard";    host = "homepage";      port = 3000;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "uptime-kuma";  host = "uptime-kuma";   port = 3001;  ws = $true;  skipAuth = $false; dns = $true }
    @{ name = "duplicati";    host = "duplicati";     port = 8200;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "adguard";      host = "adguardhome";   port = 8081;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "assistant";    host = "homeassistant"; port = 8123;  ws = $true;  skipAuth = $false; dns = $true }
    @{ name = "plex";         host = "plex";          port = 32400; ws = $false; skipAuth = $false; dns = $true }
    @{ name = "sonarr";       host = "sonarr";        port = 8989;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "radarr";       host = "radarr";        port = 7878;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "lidarr";       host = "lidarr";        port = 8686;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "bazarr";       host = "bazarr";        port = 6767;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "prowlarr";     host = "prowlarr";      port = 9696;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "readarr";      host = "readarr";       port = 8787;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "qbittorrent";  host = "qbittorrent";   port = 8080;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "overseerr";    host = "overseerr";     port = 5055;  ws = $false; skipAuth = $false; dns = $true }
    @{ name = "nginx";        host = "nginx";         port = 81;    ws = $false; skipAuth = $false; dns = $true }
)

function Get-HomelabDnsDomains {
    param([string]$Domain = "home.lab")

    $script:HomelabServices |
        Where-Object { $_.dns } |
        ForEach-Object { "$($_.name).$Domain" } |
        Sort-Object -Unique
}
