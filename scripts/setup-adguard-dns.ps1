# Configure AdGuard Home DNS rewrites for homelab *.home.lab domains.
# Usage: .\scripts\setup-adguard-dns.ps1

param(
    [string]$AdGuardUrl = "",
    [string]$Domain = "home.lab",
    [string]$HomelabHostIp = "",
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

function Test-AdGuardApiReachable {
    param([string]$BaseUrl)

    try {
        Invoke-WebRequest -Uri "$BaseUrl/control/status" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        $response = $_.Exception.Response
        if ($response -and [int]$response.StatusCode -eq 401) {
            return $true
        }
    }

    return $false
}

function Resolve-AdGuardUrl {
    param([string]$PreferredUrl)

    $candidates = @()
    if ($PreferredUrl) { $candidates += $PreferredUrl.TrimEnd('/') }
    $candidates += @(
        "http://127.0.0.1:8081",
        "http://localhost:8081",
        "http://127.0.0.1:3002",
        "http://localhost:3002"
    )

    foreach ($url in ($candidates | Select-Object -Unique)) {
        if (Test-AdGuardApiReachable -BaseUrl $url) {
            return $url
        }
    }

    throw @"
Could not reach AdGuard Home API. Tried: $($candidates -join ', ')

After first-time setup, AdGuard moves its admin API from port 3000 to port 80 inside the container.
- First-run wizard: http://localhost:3002
- Admin UI + API (after setup): http://localhost:8081

Ensure adblock-stack is running: npm run start:adblock
If you changed port mappings, pass -AdGuardUrl explicitly.
"@
}

function Get-AdGuardRewriteList {
    param([object]$Raw)

    if ($null -eq $Raw) { return @() }
    if ($Raw -is [System.Array]) { return @($Raw) }
    return @($Raw)
}

function Invoke-AdGuardApi {
    param(
        [string]$Method,
        [string]$Path,
        [PSCredential]$Credential,
        [object]$Body = $null
    )

    $uri = "$AdGuardUrl$Path"
    $params = @{
        Uri = $uri
        Method = $Method
        ErrorAction = "Stop"
    }

    if ($Credential) {
        $netCred = $Credential.GetNetworkCredential()
        $pair = "$($netCred.UserName):$($netCred.Password)"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $params.Headers = @{
            Authorization = "Basic $([Convert]::ToBase64String($bytes))"
        }
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
        Write-Info "AdGuard Home uses its own admin login from first-time setup at $AdGuardUrl."
        Write-Info "This is NOT your Authelia or NPM password."
        return Get-Credential -Message "AdGuard Home admin username and password" -UserName "admin"
    }

    return $null
}

$AdGuardUrl = Resolve-AdGuardUrl -PreferredUrl $AdGuardUrl

$envPath = Join-Path (Split-Path -Parent $PSScriptRoot) "infra-stack\.env"
$targetIp = Get-HomelabHostIp -PreferredIp $HomelabHostIp -EnvPath $envPath

Write-Info "[================================================]"
Write-Info "[       AdGuard DNS Rewrites Setup              ]"
Write-Info "[================================================]"
Write-Info "AdGuard URL: $AdGuardUrl"
Write-Info "Domain:      *.$Domain"
Write-Info ""

Write-Info "Homelab host IP: $targetIp"
Write-Info ""

$domains = Get-HomelabDnsDomains -Domain $Domain
$credential = $null
$existing = @()

try {
    $existing = Get-AdGuardRewriteList (Invoke-AdGuardApi -Method Get -Path "/control/rewrite/list" -Credential $null)
    Write-Info "AdGuard API reachable without authentication."
} catch {
    $credential = Get-AdGuardCredential
    if (-not $credential) {
        Write-Warn "Skipping DNS rewrites (no AdGuard credentials)."
        Write-Warn "Add rewrites manually in AdGuard: Filters -> DNS rewrites -> point *.$Domain to $targetIp"
        exit 0
    }
    $existing = Get-AdGuardRewriteList (Invoke-AdGuardApi -Method Get -Path "/control/rewrite/list" -Credential $credential)
}

$existingByDomain = @{}
foreach ($rule in $existing) {
    if ($rule.domain) {
        if (-not $existingByDomain.ContainsKey($rule.domain)) {
            $existingByDomain[$rule.domain] = @()
        }
        $existingByDomain[$rule.domain] += $rule
    }
}

$added = 0
$updated = 0
$skipped = 0
$deduped = 0

foreach ($hostDomain in $domains) {
    Write-Info ">> $hostDomain" -NoNewline

    $rules = if ($existingByDomain.ContainsKey($hostDomain)) {
        @($existingByDomain[$hostDomain])
    } else {
        @()
    }
    $correctRules = @($rules | Where-Object { $_.answer -eq $targetIp })
    $staleRules = @($rules | Where-Object { $_.answer -ne $targetIp })

    if ($correctRules.Count -eq 1 -and $staleRules.Count -eq 0) {
        Write-Success " [=] (already correct)"
        $skipped++
        continue
    }

    foreach ($rule in $staleRules) {
        try {
            Invoke-AdGuardApi -Method Post -Path "/control/rewrite/delete" -Credential $credential -Body @{
                domain = $hostDomain
                answer = $rule.answer
            } | Out-Null
            if ($rules.Count -gt 1) { $deduped++ }
        } catch {
            Write-Err " [-] FAILED to remove stale rewrite ($rule.answer): $($_.Exception.Message)"
        }
    }

    if ($correctRules.Count -gt 1) {
        foreach ($rule in $correctRules | Select-Object -Skip 1) {
            try {
                Invoke-AdGuardApi -Method Post -Path "/control/rewrite/delete" -Credential $credential -Body @{
                    domain = $hostDomain
                    answer = $rule.answer
                } | Out-Null
                $deduped++
            } catch {
                Write-Err " [-] FAILED to remove duplicate rewrite: $($_.Exception.Message)"
            }
        }
    }

    if ($correctRules.Count -ge 1) {
        Write-Success " [~] (updated)"
        $updated++
        continue
    }

    try {
        Invoke-AdGuardApi -Method Post -Path "/control/rewrite/add" -Credential $credential -Body @{
            domain = $hostDomain
            answer = $targetIp
        } | Out-Null

        Write-Success " [+] (added)"
        $added++
    } catch {
        Write-Err " [-] FAILED: $($_.Exception.Message)"
    }
}

Write-Info ""
Write-Info "============================================"
Write-Success "  Added:   $added"
Write-Success "  Updated: $updated"
Write-Success "  Skipped: $skipped"
if ($deduped -gt 0) {
    Write-Success "  Deduped: $deduped"
}
Write-Info ""
Write-Info "Ensure this machine uses AdGuard for DNS (port 53)."
Write-Success "Done!"
