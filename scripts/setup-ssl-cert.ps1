# Generate a *.home.lab wildcard certificate using mkcert and enable HTTPS on all NPM proxy hosts.
# mkcert installs a trusted local CA automatically — no manual cert import required.
# Idempotent: re-running always refreshes the cert files and re-uploads to NPM.
# Usage: .\scripts\setup-ssl-cert.ps1
# Requires: mkcert (winget install FiloSottile.mkcert) — installed automatically if missing.

param(
    [string]$NginxUrl  = "http://localhost:81",
    [string]$NginxUser = "admin@example.com",
    [string]$NginxPass = "changeme",
    [string]$Domain    = "home.lab",
    [string]$CertDir   = (Join-Path $PSScriptRoot "..\infra-stack\data\nginx\certs")
)

$ErrorActionPreference = "Stop"

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info    { Write-Host $args -ForegroundColor Cyan }
function Write-Warn    { Write-Host $args -ForegroundColor Yellow }
function Write-Err     { Write-Host $args -ForegroundColor Red }

# ---------------------------------------------------------------------------

function Assert-Mkcert {
    if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
        Write-Info "  mkcert not found — installing via winget..."
        winget install FiloSottile.mkcert --accept-package-agreements --accept-source-agreements
        # Refresh PATH so the new binary is visible in this session
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
        if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
            throw "mkcert install succeeded but binary not on PATH — open a new shell and re-run."
        }
    }
}

function New-WildcardCert {
    param(
        [string]$Domain,
        [string]$OutputDir
    )

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $certFile = Join-Path $OutputDir "wildcard.crt"
    $keyFile  = Join-Path $OutputDir "wildcard.key"

    Assert-Mkcert

    Write-Info "  Installing mkcert CA into system trust stores (idempotent)..."
    mkcert -install
    if ($LASTEXITCODE -ne 0) { throw "mkcert -install failed (exit $LASTEXITCODE)" }

    Write-Info "  Generating wildcard cert for *.$Domain and $Domain..."
    mkcert -cert-file $certFile -key-file $keyFile "*.$Domain" "$Domain"
    if ($LASTEXITCODE -ne 0) { throw "mkcert cert generation failed (exit $LASTEXITCODE)" }

    return @{ Cert = $certFile; Key = $keyFile }
}

function Invoke-NpmCertUpload {
    param(
        [string]   $NginxUrl,
        [hashtable]$Headers,
        [int]      $CertId,
        [string]   $CertPath,
        [string]   $KeyPath
    )

    $boundary = "boundary" + [System.Guid]::NewGuid().ToString("N")
    $CRLF     = "`r`n"
    $certPem  = Get-Content $CertPath -Raw
    $keyPem   = Get-Content $KeyPath  -Raw

    $body = "--$boundary$CRLF" +
        "Content-Disposition: form-data; name=`"certificate`"; filename=`"wildcard.crt`"$CRLF" +
        "Content-Type: text/plain$CRLF$CRLF" +
        "$certPem$CRLF" +
        "--$boundary$CRLF" +
        "Content-Disposition: form-data; name=`"certificate_key`"; filename=`"wildcard.key`"$CRLF" +
        "Content-Type: text/plain$CRLF$CRLF" +
        "$keyPem$CRLF" +
        "--$boundary--$CRLF"

    Invoke-RestMethod `
        -Uri         "$NginxUrl/api/nginx/certificates/$CertId/upload" `
        -Method      Post `
        -Headers     $Headers `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body        ([System.Text.Encoding]::ASCII.GetBytes($body)) `
        -ErrorAction Stop | Out-Null
}

function Remove-StaleRootCert {
    param([string]$Subject)
    $stale = Get-ChildItem Cert:\LocalMachine\Root |
        Where-Object { $_.Subject -like "*$Subject*" -and $_.Issuer -eq $_.Subject }
    foreach ($c in $stale) {
        try {
            $c | Remove-Item -Force
            Write-Warn "  Removed stale self-signed cert: $($c.Thumbprint) ($($c.Subject))"
        } catch {
            Write-Warn "  Could not remove $($c.Thumbprint) — run as Administrator to clean it up."
        }
    }
}

# ---------------------------------------------------------------------------

Write-Info "[================================================]"
Write-Info "[  NPM Wildcard TLS Setup - *.$Domain          ]"
Write-Info "[================================================]"
Write-Info ""

try {
    # STEP 1 — generate cert via mkcert (always regenerates)
    Write-Info "STEP 1: Generating wildcard certificate for *.$Domain via mkcert..."
    $certPaths = New-WildcardCert -Domain $Domain -OutputDir $CertDir
    Write-Success "[+] Certificate : $($certPaths.Cert)"
    Write-Success "[+] Private key  : $($certPaths.Key)"
    Write-Info ""

    # STEP 2 — authenticate to NPM
    Write-Info "STEP 2: Authenticating to NGINX PM at $NginxUrl..."
    $loginResp = Invoke-RestMethod `
        -Uri         "$NginxUrl/api/tokens" `
        -Method      Post `
        -Body        (@{ identity = $NginxUser; secret = $NginxPass } | ConvertTo-Json) `
        -ContentType "application/json" `
        -ErrorAction Stop

    $headers = @{ Authorization = "Bearer $($loginResp.token)" }
    Write-Success "[+] Authenticated"
    Write-Info ""

    # STEP 3 — upload cert to NPM (create record if new, always re-upload files)
    Write-Info "STEP 3: Uploading certificate to NPM..."
    $niceName = "*.$Domain Wildcard"

    $existingCerts = Invoke-RestMethod -Uri "$NginxUrl/api/nginx/certificates" `
        -Headers $headers -Method Get -ErrorAction Stop
    if ($existingCerts -isnot [System.Array]) { $existingCerts = @($existingCerts) }

    $existing = $existingCerts | Where-Object { $_.nice_name -eq $niceName } | Select-Object -First 1

    if ($existing) {
        $certId = $existing.id
        Write-Info "  Cert record exists (id $certId) — re-uploading fresh files..."
    } else {
        $record = Invoke-RestMethod `
            -Uri         "$NginxUrl/api/nginx/certificates" `
            -Method      Post `
            -Headers     $headers `
            -Body        (@{ provider = "other"; nice_name = $niceName } | ConvertTo-Json) `
            -ContentType "application/json" `
            -ErrorAction Stop
        $certId = $record.id
        Write-Info "  Created new cert record (id $certId)..."
    }

    Invoke-NpmCertUpload -NginxUrl $NginxUrl -Headers $headers `
        -CertId $certId -CertPath $certPaths.Cert -KeyPath $certPaths.Key
    Write-Success "[+] Uploaded (id $certId)"
    Write-Info ""

    # STEP 4 — enable HTTPS on all proxy hosts
    Write-Info "STEP 4: Enabling HTTPS on all proxy hosts..."
    Write-Info "============================================"

    $proxyHosts = Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts" `
        -Headers $headers -Method Get -ErrorAction Stop
    if ($proxyHosts -isnot [System.Array]) { $proxyHosts = @($proxyHosts) }

    $updated = 0; $skipped = 0; $failed = 0

    foreach ($ph in $proxyHosts) {
        $label = ($ph.domain_names -join ", ")
        Write-Info ">> $label" -NoNewline

        if ($ph.certificate_id -eq $certId) {
            Write-Warn " [=] (already on this cert)"
            $skipped++
            continue
        }

        try {
            $updateBody = @{
                domain_names            = @($ph.domain_names)
                forward_scheme          = $ph.forward_scheme
                forward_host            = $ph.forward_host
                forward_port            = [int]$ph.forward_port
                access_list_id          = 0
                certificate_id          = [int]$certId
                ssl_forced              = $true
                caching_enabled         = $false
                block_exploits          = $false
                advanced_config         = [string]$ph.advanced_config
                allow_websocket_upgrade = [bool]$ph.allow_websocket_upgrade
                http2_support           = $true
                hsts_enabled            = $false
                hsts_subdomains         = $false
                trust_forwarded_proto   = $false
                locations               = @()
            } | ConvertTo-Json

            Invoke-RestMethod -Uri "$NginxUrl/api/nginx/proxy-hosts/$($ph.id)" `
                -Method Put -Headers $headers -Body $updateBody `
                -ContentType "application/json" -ErrorAction Stop | Out-Null

            Write-Success " [+] (HTTPS enabled)"
            $updated++

        } catch {
            Write-Err " [-] FAILED: $($_.Exception.Message)"
            $failed++
        }
    }

    Write-Info ""
    Write-Info "============================================"
    Write-Info "RESULTS:"
    Write-Success "  [+] Updated : $updated"
    if ($skipped -gt 0) { Write-Warn "  [=] Skipped : $skipped" }
    if ($failed  -gt 0) { Write-Err  "  [-] Failed  : $failed" }
    Write-Info ""

    # STEP 5 — remove any leftover self-signed certs for this domain
    Write-Info "STEP 5: Cleaning up stale self-signed certs from Windows trust store..."
    Remove-StaleRootCert -Subject $Domain
    Write-Info ""

    Write-Success "[+] TLS setup complete!"
    Write-Info ""
    Write-Info "The mkcert CA is already trusted on this machine."
    Write-Warn "For other devices (phones, other PCs), copy and install the CA cert:"
    $caRoot = & mkcert -CAROOT
    Write-Warn "  $caRoot\rootCA.pem"

} catch {
    Write-Err "[-] Setup failed: $($_.Exception.Message)"
    exit 1
}
