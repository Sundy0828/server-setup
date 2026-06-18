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

function Get-AutheliaNpmAdvancedConfig {
    param([string]$Domain)

    # Use $user/$groups/$name/$email — not $remote_user, which conflicts with nginx built-ins.
    return @"
location = /authelia/api/verify {
    internal;
    proxy_pass https://authelia.home.lab/api/verify;
    proxy_ssl_verify off;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL `$scheme://`$http_host`$request_uri;
    proxy_set_header X-Forwarded-Proto `$scheme;
    proxy_set_header X-Forwarded-For `$remote_addr;
}

location / {
    auth_request /authelia/api/verify;
    error_page 401 =302 http://authelia.$Domain/?rd=`$scheme://`$http_host`$request_uri;
    auth_request_set `$user `$upstream_http_remote_user;
    auth_request_set `$groups `$upstream_http_remote_groups;
    auth_request_set `$name `$upstream_http_remote_name;
    auth_request_set `$email `$upstream_http_remote_email;
    proxy_set_header Remote-User `$user;
    proxy_set_header Remote-Groups `$groups;
    proxy_set_header Remote-Name `$name;
    proxy_set_header Remote-Email `$email;
    proxy_pass `$forward_scheme://`$server:`$port;
}
"@
}

function Test-ProxyHostNeedsRepair {
    param(
        [object]$ProxyHost,
        [bool]$UseAuth
    )

    if ($UseAuth) {
        $config = [string]$ProxyHost.advanced_config
        if ($config -match '\$remote_user|\$remote_groups|\$remote_name|\$remote_email') {
            return $true
        }
        if ($config -match 'proxy_pass\s+http://authelia:9091/api/verify') {
            return $true
        }
    }

    $meta = $ProxyHost.meta
    if ($null -eq $meta) { return $false }

    if ($meta.PSObject.Properties['nginx_online'] -and $meta.nginx_online -eq $false) {
        return $true
    }

    if ($meta.PSObject.Properties['nginx_err'] -and $meta.nginx_err) {
        return $true
    }

    return $false
}

function New-NpmProxyHostBody {
    param(
        [object]$Service,
        [string]$Domain,
        [bool]$UseAuth
    )

    $body = [ordered]@{
        domain_names = @("$($Service.name).$Domain")
        forward_scheme = "http"
        forward_host = $Service.host
        forward_port = $Service.port
        allow_websocket_upgrade = [bool]$Service.ws
    }

    if ($UseAuth) {
        $body.advanced_config = Get-AutheliaNpmAdvancedConfig -Domain $Domain
    }

    return $body
}

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
    $existingHosts = Get-NpmProxyHostList (Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts" `
        -Headers $headers -Method Get -ErrorAction Stop)

    $hostsByDomain = @{}
    foreach ($proxyHost in $existingHosts) {
        foreach ($name in (Get-ProxyHostDomainNames $proxyHost)) {
            $key = $name.ToLower()
            if (-not $hostsByDomain.ContainsKey($key)) {
                $hostsByDomain[$key] = @()
            }
            $hostsByDomain[$key] += $proxyHost
        }
    }

    $dedupCount = 0
    foreach ($key in @($hostsByDomain.Keys)) {
        $hosts = $hostsByDomain[$key]
        if ($hosts.Count -le 1) { continue }

        for ($i = 1; $i -lt $hosts.Count; $i++) {
            try {
                Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts/$($hosts[$i].id)" `
                    -Headers $headers -Method Delete -ErrorAction Stop | Out-Null
                $dedupCount++
            } catch {
                Write-Warn "Could not remove duplicate proxy host for '$key' (id $($hosts[$i].id)): $($_.Exception.Message)"
            }
        }
        $hostsByDomain[$key] = @($hosts[0])
    }

    $existingDomains = @{}
    foreach ($key in $hostsByDomain.Keys) {
        $existingDomains[$key] = $hostsByDomain[$key][0]
    }

    Write-Info "[+] Found $($existingHosts.Count) existing proxy host(s)"
    if ($dedupCount -gt 0) {
        Write-Warn "[+] Removed $dedupCount duplicate proxy host(s)"
    }
    Write-Info ""

    Write-Info "STEP 3: Creating proxy hosts..."
    Write-Info "============================================"
    Write-Info ""

    $successCount = 0
    $repairCount = 0
    $skipCount = 0
    $failCount = 0

    foreach ($service in $script:HomelabServices) {
        $domainName = "$($service.name).$Domain"
        $useAuth = -not $service.skipAuth
        $domainKey = $domainName.ToLower()

        Write-Info ">> $($service.name)" -NoNewline

        try {
            if ($existingDomains.ContainsKey($domainKey)) {
                $existingHost = $existingDomains[$domainKey]

                if (-not (Test-ProxyHostNeedsRepair -ProxyHost $existingHost -UseAuth:$useAuth)) {
                    Write-Warn " [=] (already exists)"
                    $skipCount++
                    continue
                }

                $proxyHostBody = New-NpmProxyHostBody -Service $service -Domain $Domain -UseAuth:$useAuth
                Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts/$($existingHost.id)" `
                    -Headers $headers `
                    -Method Put `
                    -Body ($proxyHostBody | ConvertTo-Json) `
                    -ContentType "application/json" `
                    -ErrorAction Stop | Out-Null

                if ($useAuth) {
                    Write-Success " [~] (repaired Authelia auth config)"
                } else {
                    Write-Success " [~] (repaired)"
                }

                $repairCount++
                continue
            }

            $proxyHostBody = New-NpmProxyHostBody -Service $service -Domain $Domain -UseAuth:$useAuth
            Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts" `
                -Headers $headers `
                -Method Post `
                -Body ($proxyHostBody | ConvertTo-Json) `
                -ContentType "application/json" `
                -ErrorAction Stop | Out-Null

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
    if ($repairCount -gt 0) {
        Write-Success "  [~] Repaired: $repairCount"
    }
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
