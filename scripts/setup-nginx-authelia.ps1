# Automated NGINX Proxy Manager + Authelia Setup
# Creates proxy hosts for all services with forward authentication
# Usage: .\scripts\setup-nginx-authelia.ps1

param(
    [string]$NginxUrl = "http://localhost:81",
    [string]$NginxUser = "admin@example.com",
    [string]$NginxPass = "changeme",
    [string]$Domain = "home.lab"
)

$ErrorActionPreference = "Stop"

# Color output
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

# Services configuration: @{name, host, port, websocket, skipAuth}
$services = @(
    @{name="authelia"; host="authelia"; port=9091; ws=$false; skipAuth=$true}
    @{name="homepage"; host="homepage"; port=3000; ws=$false; skipAuth=$false}
    @{name="portainer"; host="portainer"; port=9000; ws=$false; skipAuth=$false}
    @{name="uptime-kuma"; host="uptime-kuma"; port=3001; ws=$true; skipAuth=$false}
    @{name="adguard"; host="adguardhome"; port=3000; ws=$false; skipAuth=$false}
    @{name="home"; host="homeassistant"; port=8123; ws=$true; skipAuth=$false}
    @{name="plex"; host="plex"; port=32400; ws=$false; skipAuth=$false}
    @{name="sonarr"; host="sonarr"; port=8989; ws=$false; skipAuth=$false}
    @{name="radarr"; host="radarr"; port=7878; ws=$false; skipAuth=$false}
    @{name="lidarr"; host="lidarr"; port=8686; ws=$false; skipAuth=$false}
    @{name="bazarr"; host="bazarr"; port=6767; ws=$false; skipAuth=$false}
    @{name="prowlarr"; host="prowlarr"; port=9696; ws=$false; skipAuth=$false}
    @{name="readarr"; host="readarr"; port=8787; ws=$false; skipAuth=$false}
    @{name="qbittorrent"; host="qbittorrent"; port=8080; ws=$false; skipAuth=$false}
    @{name="overseerr"; host="overseerr"; port=5055; ws=$false; skipAuth=$false}
)

try {
    # Step 1: Authenticate
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
    Write-Success "[+] Authenticated successfully"

    Write-Info "STEP 2: Skipping SSL (using HTTP proxies)"
    Write-Info ""

    # Step 3: Create proxy hosts
    Write-Info "STEP 3: Creating proxy hosts..."
    Write-Info "============================================"
    Write-Info ""

    $successCount = 0
    $failCount = 0

    foreach ($service in $services) {
        $domainName = "$($service.name).$Domain"
        $useAuth = -not $service.skipAuth
        
        Write-Info ">> $($service.name)" -NoNewline

        try {
            # Create proxy host (HTTP, no SSL)
            $proxyHostBody = @{
                domain_names = @($domainName)
                forward_scheme = "http"
                forward_host = $service.host
                forward_port = $service.port
                certificate_id = 0
                ssl_forced = $false
                http2_support = $false
                websockets_support = $service.ws
                block_exploits = $true
                caching_enabled = $false
            } | ConvertTo-Json

            $proxyResponse = Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts" `
                -Headers @{Authorization = "Bearer $token"} `
                -Method Post `
                -Body $proxyHostBody `
                -ContentType "application/json" `
                -ErrorAction Stop

            $proxyId = $proxyResponse.id

            # Add Authelia forward auth if needed
            if ($useAuth) {
                $authLocationBody = @{
                    path = "/"
                    forward_scheme = "http"
                    forward_host = "authelia"
                    forward_port = 9091
                    auth_forward = $true
                    auth_forward_uri = "/api/verify?rd=https://`$host/"
                    custom_nginx_upstream = ""
                    custom_nginx_location = "auth_request_set `$remote_user `$upstream_http_remote_user;`nauth_request_set `$remote_groups `$upstream_http_remote_groups;`nauth_request_set `$remote_name `$upstream_http_remote_name;`nauth_request_set `$remote_email `$upstream_http_remote_email;"
                } | ConvertTo-Json

                Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts/$proxyId/locations" `
                    -Headers @{Authorization = "Bearer $token"} `
                    -Method Post `
                    -Body $authLocationBody `
                    -ContentType "application/json" `
                    -ErrorAction Stop | Out-Null

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
    if ($failCount -gt 0) {
        Write-Err "  [-] Failed:  $failCount"
    }

    Write-Info ""
    Write-Success "[+] Setup complete!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "1. Access NGINX PM at: $NginxUrl"
    Write-Info "2. Verify proxy hosts are created"
    Write-Info "3. Access your services at: http://<service>.$Domain"
    Write-Info ""
    Write-Info "Example URLs:"
    Write-Info "  - http://homepage.$Domain"
    Write-Info "  - http://portainer.$Domain"
    Write-Info "  - http://sonarr.$Domain"

} catch {
    Write-Err "[-] Setup failed: $($_.Exception.Message)"
    exit 1
}
