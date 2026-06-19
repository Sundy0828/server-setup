# run-arr-setup.ps1
# Windows launcher for arr-setup.sh.
# Run this from the plex-stack directory after `docker compose up -d`.
# Right-click → "Run with PowerShell", or: .\run-arr-setup.ps1

param(
    [string]$QbPassword = $env:QB_PASSWORD
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Prompt for qBittorrent password if not provided
if (-not $QbPassword) {
    $secPwd = Read-Host "qBittorrent password (leave blank to skip download client setup)" -AsSecureString
    $QbPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
    )
}

# Verify Docker is running
if (-not (docker info 2>$null)) {
    Write-Error "Docker is not running. Start Docker Desktop and try again."
    exit 1
}

Write-Host "Starting arr-setup via Docker..." -ForegroundColor Cyan

docker run --rm `
    --network homelab `
    -v "${ScriptDir}:/setup" `
    -e SONARR_URL=http://sonarr:8989 `
    -e RADARR_URL=http://radarr:7878 `
    -e LIDARR_URL=http://lidarr:8686 `
    -e READARR_URL=http://readarr:8787 `
    -e PROWLARR_URL=http://prowlarr:9696 `
    -e BAZARR_URL=http://bazarr:6767 `
    -e QB_PASSWORD=$QbPassword `
    alpine sh -c "apk add --no-cache bash curl jq python3 > /dev/null 2>&1 && bash /setup/arr-setup.sh"
