# Automated NGINX Proxy Manager + Authelia Setup
# Creates proxy hosts for all services with forward authentication.
# Idempotent: skips hosts that already exist.
# Usage: .\scripts\setup-nginx-authelia.ps1

param(
    [string]$NginxUrl = "http://localhost:81",
    [string]$NginxUser = "admin@example.com",
    [string]$NginxPass = "changeme",
    [string]$Domain = "home.lab"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\homelab-services.ps1"

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warn { Write-Host $args -ForegroundColor Yellow }
function Write-Err { Write-Host $args -ForegroundColor Red }

Write-Info "[================================================]"
Write-Info "[  NGINX Proxy Manager + Authelia Auto Setup   ]"
Write-Info "[================================================]"
Write-Info "Target Domain: $Domain"
Write-Info "NGINX PM URL:  $NginxUrl"
Write-Info ""

try {
    Write-Info "STEP 1: Authenticating to NGINX PM..."
    $loginBody = @{
        identity = $NginxUser
        secret = $NginxPass
    } | ConvertTo-Json

    $loginResponse = Invoke-RestMethod -Uri "$NginxUrl/api/tokens" `
        -Method Post `
        -Body $loginBody `
        -ContentType "application/json" `
        -ErrorAction Stop

    $token = $loginResponse.token
    $headers = @{ Authorization = "Bearer $token" }
    Write-Success "[+] Authenticated successfully"
    Write-Info ""

    Write-Info "STEP 2: Loading existing proxy hosts..."
    $existingHosts = @(Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts" `
        -Headers $headers -Method Get -ErrorAction Stop)

    $existingDomains = @{}
    foreach ($proxyHost in $existingHosts) {
        foreach ($name in $proxyHost.domain_names) {
            $existingDomains[$name.ToLower()] = $proxyHost
        }
    }
    Write-Info "[+] Found $($existingHosts.Count) existing proxy host(s)"
    Write-Info ""

    Write-Info "STEP 3: Creating proxy hosts..."
    Write-Info "============================================"
    Write-Info ""

    $successCount = 0
    $skipCount = 0
    $failCount = 0

    foreach ($service in $script:HomelabServices) {
        $domainName = "$($service.name).$Domain"
        $useAuth = -not $service.skipAuth

        Write-Info ">> $($service.name)" -NoNewline

        if ($existingDomains.ContainsKey($domainName.ToLower())) {
            Write-Warn " [=] (already exists)"
            $skipCount++
            continue
        }

        try {
            $proxyHostBody = [ordered]@{
                domain_names = @($domainName)
                forward_scheme = "http"
                forward_host = $service.host
                forward_port = $service.port
                allow_websocket_upgrade = [bool]$service.ws
            }

            if ($useAuth) {
                $proxyHostBody.advanced_config = @"
location = /authelia/api/verify {
    internal;
    proxy_pass http://authelia:9091/api/verify;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL `$scheme://`$http_host`$request_uri;
    proxy_set_header X-Forwarded-Proto `$scheme;
    proxy_set_header X-Forwarded-For `$remote_addr;
}

location / {
    auth_request /authelia/api/verify;
    error_page 401 =302 http://authelia.$Domain/?rd=`$scheme://`$http_host`$request_uri;
    auth_request_set `$remote_user `$upstream_http_remote_user;
    auth_request_set `$remote_groups `$upstream_http_remote_groups;
    auth_request_set `$remote_name `$upstream_http_remote_name;
    auth_request_set `$remote_email `$upstream_http_remote_email;
    proxy_set_header Remote-User `$remote_user;
    proxy_set_header Remote-Groups `$remote_groups;
    proxy_set_header Remote-Name `$remote_name;
    proxy_set_header Remote-Email `$remote_email;
    proxy_pass `$forward_scheme://`$server:`$port;
}
"@
            }

            $proxyResponse = Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts" `
                -Headers $headers `
                -Method Post `
                -Body ($proxyHostBody | ConvertTo-Json) `
                -ContentType "application/json" `
                -ErrorAction Stop

            if ($useAuth) {
                Write-Success " [+] (with Authelia auth)"
            } else {
                Write-Success " [+]"
            }

            $successCount++

        } catch {
            Write-Err " [-] FAILED: $($_.Exception.Message)"
            $failCount++
        }
    }

    Write-Info ""
    Write-Info "============================================"
    Write-Info "RESULTS:"
    Write-Success "  [+] Created: $successCount"
    if ($skipCount -gt 0) {
        Write-Warn "  [=] Skipped: $skipCount"
    }
    if ($failCount -gt 0) {
        Write-Err "  [-] Failed:  $failCount"
    }

    Write-Info ""
    Write-Success "[+] NPM setup complete!"
    Write-Info ""
    Write-Info "Access services at: http://<service>.$Domain"
    Write-Info "  http://sonarr.$Domain"
    Write-Info "  http://plex.$Domain"
    Write-Info "  http://authelia.$Domain"

} catch {
    Write-Err "[-] Setup failed: $($_.Exception.Message)"
    exit 1
}
