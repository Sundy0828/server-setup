# Set AuthenticationMethod=External on all *arr apps so Authelia (reverse proxy) handles auth.
# The apps' built-in login page is suppressed; Authelia enforces access at the proxy level.
# Usage: .\scripts\set-arr-auth-external.ps1
#        .\scripts\set-arr-auth-external.ps1 -PlexStackPath "D:\stacks\plex-stack" -WhatIf

param(
    [string]$PlexStackPath = "",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info    { Write-Host $args -ForegroundColor Cyan }
function Write-Warn    { Write-Host $args -ForegroundColor Yellow }
function Write-Err     { Write-Host $args -ForegroundColor Red }

if (-not $PlexStackPath) {
    $PlexStackPath = Join-Path (Split-Path -Parent $PSScriptRoot) "plex-stack"
}

if (-not (Test-Path $PlexStackPath)) {
    Write-Err "plex-stack directory not found: $PlexStackPath"
    exit 1
}

# *arr apps that use config.xml with an AuthenticationMethod element.
# Bazarr and Overseerr use different config formats and are excluded.
$arrApps = @("sonarr", "radarr", "lidarr", "prowlarr", "readarr")

$changed = @()
$skipped = @()
$missing = @()

foreach ($app in $arrApps) {
    $configPath = Join-Path $PlexStackPath "config\$app\config.xml"

    if (-not (Test-Path $configPath)) {
        Write-Warn "${app}: config.xml not found at $configPath - skipping"
        $missing += $app
        continue
    }

    $xml = [xml](Get-Content $configPath -Raw)
    $current = $xml.Config.AuthenticationMethod

    if ($current -eq "External") {
        Write-Info "${app}: already External - no change"
        $skipped += $app
        continue
    }

    Write-Info "${app}: $current -> External"

    if (-not $WhatIf) {
        $xml.Config.AuthenticationMethod = "External"
        $xml.Save($configPath)
    }

    $changed += $app
}

if ($WhatIf) {
    Write-Warn "WhatIf mode - no files written, no containers restarted"
    exit 0
}

if ($changed.Count -eq 0) {
    Write-Success "All apps already set to External. Nothing to restart."
    exit 0
}

Write-Info ""
Write-Info "Restarting containers to apply changes: $($changed -join ', ')"

foreach ($app in $changed) {
    Write-Info "  Restarting ${app}..."
    docker restart $app
    if (-not $?) {
        Write-Warn "  docker restart ${app} failed - it may not be running"
    }
}

Write-Info ""
Write-Success "Done."
Write-Success "  Changed : $($changed -join ', ')"
if ($skipped.Count) { Write-Info "  Skipped : $($skipped -join ', ') (already External)" }
if ($missing.Count) { Write-Warn "  Missing : $($missing -join ', ') (no config.xml found)" }
