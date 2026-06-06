# Configure AdGuard Home DNS rewrites for homelab *.home.lab domains.
# Usage: .\scripts\setup-adguard-dns.ps1

param(
    [string]$AdGuardUrl = "http://localhost:3002",
    [string]$Domain = "home.lab",
    [string]$NginxContainer = "nginx-pm",
    [string]$AdGuardUser = "",
    [string]$AdGuardPass = "",
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\homelab-services.ps1"

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warn { Write-Host $args -ForegroundColor Yellow }
function Write-Err { Write-Host $args -ForegroundColor Red }

function Get-NginxPmIp {
    param([string]$ContainerName)

    $ip = docker inspect $ContainerName --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>$null
    if (-not $ip) {
        throw "Could not resolve IP for container '$ContainerName'. Is infra-stack running?"
    }
    return $ip.Trim()
}

function Invoke-AdGuardApi {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Credential,
        [object]$Body = $null
    )

    $uri = "$AdGuardUrl$Path"
    $params = @{
        Uri = $uri
        Method = $Method
        ErrorAction = "Stop"
    }

    if ($Credential) {
        $params.Credential = $Credential
    }

    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Compress)
        $params.ContentType = "application/json"
    }

    return Invoke-RestMethod @params
}

function Get-AdGuardCredential {
    if ($AdGuardUser -and $AdGuardPass) {
        return [PSCredential]::new($AdGuardUser, (ConvertTo-SecureString $AdGuardPass -AsPlainText -Force))
    }

    if (-not $SkipPrompt) {
        Write-Info ""
        Write-Info "AdGuard requires credentials (set during first-time setup at $AdGuardUrl)."
        return Get-Credential -Message "AdGuard Home admin credentials" -UserName "admin"
    }

    return $null
}

Write-Info "[================================================]"
Write-Info "[       AdGuard DNS Rewrites Setup              ]"
Write-Info "[================================================]"
Write-Info "AdGuard URL: $AdGuardUrl"
Write-Info "Domain:      *.$Domain"
Write-Info ""

$nginxIp = Get-NginxPmIp -ContainerName $NginxContainer
Write-Info "NPM container IP: $nginxIp"
Write-Info ""

$domains = Get-HomelabDnsDomains -Domain $Domain
$credential = $null
$existing = @()

try {
    $existing = @(Invoke-AdGuardApi -Method Get -Path "/control/rewrite/list" -Credential $null)
    Write-Info "AdGuard API reachable without authentication."
} catch {
    $credential = Get-AdGuardCredential
    if (-not $credential) {
        Write-Warn "Skipping DNS rewrites (no AdGuard credentials)."
        Write-Warn "Add rewrites manually in AdGuard: Filters -> DNS rewrites -> point *.$Domain to $nginxIp"
        exit 0
    }
    $existing = @(Invoke-AdGuardApi -Method Get -Path "/control/rewrite/list" -Credential $credential)
}

$existingByDomain = @{}
foreach ($rule in $existing) {
    if ($rule.domain) {
        $existingByDomain[$rule.domain] = $rule
    }
}

$added = 0
$updated = 0
$skipped = 0

foreach ($hostDomain in $domains) {
    Write-Info ">> $hostDomain" -NoNewline

    if ($existingByDomain.ContainsKey($hostDomain)) {
        $rule = $existingByDomain[$hostDomain]
        if ($rule.answer -eq $nginxIp) {
            Write-Success " [=] (already correct)"
            $skipped++
            continue
        }

        try {
            Invoke-AdGuardApi -Method Post -Path "/control/rewrite/delete" -Credential $credential -Body @{
                domain = $hostDomain
                answer = $rule.answer
            } | Out-Null
        } catch {
            Write-Err " [-] FAILED to remove stale rewrite: $($_.Exception.Message)"
            continue
        }
    }

    try {
        Invoke-AdGuardApi -Method Post -Path "/control/rewrite/add" -Credential $credential -Body @{
            domain = $hostDomain
            answer = $nginxIp
        } | Out-Null

        if ($existingByDomain.ContainsKey($hostDomain)) {
            Write-Success " [~] (updated)"
            $updated++
        } else {
            Write-Success " [+] (added)"
            $added++
        }
    } catch {
        Write-Err " [-] FAILED: $($_.Exception.Message)"
    }
}

Write-Info ""
Write-Info "============================================"
Write-Success "  Added:   $added"
Write-Success "  Updated: $updated"
Write-Success "  Skipped: $skipped"
Write-Info ""
Write-Info "Ensure this machine uses AdGuard for DNS (port 53)."
Write-Success "Done!"
