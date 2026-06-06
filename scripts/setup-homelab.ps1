# One-time homelab bootstrap: configs, stacks, NPM routes, AdGuard DNS, Authelia SSO.
# Interactive only for secrets/passwords that cannot be pre-generated safely.
# Usage: npm run setup

param(
    [string]$Domain = "home.lab",
    [string]$NginxUrl = "http://localhost:81",
    [string]$AdGuardUrl = "http://localhost:3002",
    [switch]$SkipStart,
    [switch]$SkipNginx,
    [switch]$SkipDns,
    [switch]$SkipStacks
)

$ErrorActionPreference = "Stop"

$ScriptRoot = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $ScriptRoot

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warn { Write-Host $args -ForegroundColor Yellow }
function Write-Err { Write-Host $args -ForegroundColor Red }

function Wait-ForHttp {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 120,
        [string]$Label = $Url
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Info "Waiting for $Label ..."

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                Write-Success "[+] $Label is ready"
                return $true
            }
        } catch {
            Start-Sleep -Seconds 3
        }
    }

    throw "Timed out waiting for $Label"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-AutheliaTemplates {
    param(
        [string]$Domain,
        [string]$ConfigDir
    )

    $templateDir = Join-Path $ProjectRoot "infra-stack\templates\authelia"
    $configFile = Join-Path $ConfigDir "configuration.yml"
    $usersFile = Join-Path $ConfigDir "users_database.yml"
    $notifyFile = Join-Path $ConfigDir "notification.txt"

    Ensure-Directory $ConfigDir

    if (-not (Test-Path $configFile)) {
        $template = Get-Content (Join-Path $templateDir "configuration.yml.example") -Raw
        $template.Replace("{{DOMAIN}}", $Domain) | Set-Content $configFile -NoNewline
        Write-Success "[+] Created configuration.yml for domain '$Domain'"
    } else {
        Write-Info "[=] configuration.yml already exists (skipping)"
    }

    if (-not (Test-Path $usersFile)) {
        Copy-Item (Join-Path $templateDir "users_database.yml.example") $usersFile
        Write-Success "[+] Created users_database.yml (passwords still needed)"
    } else {
        Write-Info "[=] users_database.yml already exists"
    }

    if (-not (Test-Path $notifyFile)) {
        "" | Set-Content $notifyFile
    }
}

function Test-EnvNeedsSecrets {
    param([string]$EnvPath)

    if (-not (Test-Path $EnvPath)) { return $true }

    $content = Get-Content $EnvPath -Raw
    $placeholders = @(
        "your-jwt-secret-here",
        "your-session-secret-here",
        "your-encryption-key-here"
    )

    foreach ($key in @("AUTHELIA_JWT_SECRET", "AUTHELIA_SESSION_SECRET", "AUTHELIA_STORAGE_ENCRYPTION_KEY")) {
        if ($content -notmatch "$key=.+") { return $true }
        foreach ($placeholder in $placeholders) {
            if ($content -match "$key=$placeholder") { return $true }
        }
    }

    return $false
}

function Test-UsersNeedSetup {
    param([string]$UsersPath)

    if (-not (Test-Path $UsersPath)) { return $true }

    $content = Get-Content $UsersPath -Raw
    if ($content -match "users:\s*\{\s*\}") { return $true }
    if ($content -notmatch '\$argon2') { return $true }

    return $false
}

Write-Info ""
Write-Info "[====================================================]"
Write-Info "[           Homelab Bootstrap Setup                  ]"
Write-Info "[====================================================]"
Write-Info "Domain: $Domain"
Write-Info ""

# Step 1: Docker network
Write-Info "STEP 1: Docker network"
$net = docker network ls --filter name=homelab --quiet 2>$null
if (-not $net) {
    docker network create homelab | Out-Null
}
Write-Success "[+] Network 'homelab' ready"
Write-Info ""

# Step 2: Environment file
Write-Info "STEP 2: Environment file"
$envPath = Join-Path $ProjectRoot "infra-stack\.env"
$envExample = Join-Path $ProjectRoot "infra-stack\.env.example"
if (-not (Test-Path $envPath) -and (Test-Path $envExample)) {
    Copy-Item $envExample $envPath
    Write-Success "[+] Created infra-stack/.env from .env.example"
} else {
    Write-Info "[=] infra-stack/.env already exists"
}
Write-Info ""

# Step 3: Authelia config templates
Write-Info "STEP 3: Authelia configuration templates"
$configDir = Join-Path $ProjectRoot "infra-stack\config\authelia"
Copy-AutheliaTemplates -Domain $Domain -ConfigDir $configDir
Write-Info ""

# Step 4: Secrets and user passwords (interactive when needed)
Write-Info "STEP 4: Authelia secrets and users"
$usersPath = Join-Path $configDir "users_database.yml"
$needsSecrets = Test-EnvNeedsSecrets -EnvPath $envPath
$needsUsers = Test-UsersNeedSetup -UsersPath $usersPath

if ($needsSecrets -or $needsUsers) {
    $autheliaArgs = @()
    if (-not $needsSecrets) { $autheliaArgs += "-SkipSecrets" }
    if (-not $needsUsers) { $autheliaArgs += "-SkipUsers" }

    if ($needsSecrets) {
        Write-Info "Generating Authelia secrets -> infra-stack/.env"
    }
    if ($needsUsers) {
        Write-Info "You will be prompted for SSO user passwords (admin, reg)."
    }

    & "$ScriptRoot\setup-authelia.ps1" @autheliaArgs
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
} else {
    Write-Success "[+] Authelia secrets and users already configured"
}
Write-Info ""

# Step 5: Start stacks
if (-not $SkipStart) {
    Write-Info "STEP 5: Starting Docker stacks"
    Write-Info "  -> adblock-stack"
    Push-Location (Join-Path $ProjectRoot "adblock-stack")
    docker compose up -d
    Pop-Location

    Write-Warn ""
    Write-Warn "If this is the first AdGuard run, complete setup at $AdGuardUrl"
    Write-Warn "Use any admin username/password — you will enter it again for DNS rewrites."
    Write-Warn ""

    try {
        Wait-ForHttp -Url $AdGuardUrl -Label "AdGuard Home"
    } catch {
        Write-Warn $_.Exception.Message
        Write-Warn "Continuing — finish AdGuard setup, then re-run: npm run setup:dns"
    }

    Write-Info "  -> infra-stack"
    Push-Location (Join-Path $ProjectRoot "infra-stack")
    docker compose up -d
    Pop-Location

    try {
        Wait-ForHttp -Url $NginxUrl -Label "Nginx Proxy Manager"
        Wait-ForHttp -Url "http://localhost:9091/api/state" -Label "Authelia"
    } catch {
        Write-Warn $_.Exception.Message
    }

    if (-not $SkipStacks) {
        foreach ($stack in @("homeassistant-stack", "plex-stack")) {
            $stackPath = Join-Path $ProjectRoot $stack
            if (Test-Path (Join-Path $stackPath "compose.yml")) {
                Write-Info "  -> $stack"
                Push-Location $stackPath
                docker compose up -d
                Pop-Location
            }
        }
    }
    Write-Info ""
} else {
    Write-Info "STEP 5: Skipped stack startup (-SkipStart)"
    Write-Info ""
}

# Step 6: NPM proxy hosts + Authelia forward auth
if (-not $SkipNginx) {
    Write-Info "STEP 6: Nginx Proxy Manager routes + SSO"
    Write-Info "Default NPM login: admin@example.com / changeme (change after setup)"
    Write-Info ""

    $nginxUser = "admin@example.com"
    $nginxPassPlain = "changeme"
    $customPass = Read-Host "NPM admin password [Enter = changeme]"
    if ($customPass) {
        $nginxPassPlain = $customPass
    }

    & "$ScriptRoot\setup-nginx-authelia.ps1" `
        -NginxUrl $NginxUrl `
        -NginxUser $nginxUser `
        -NginxPass $nginxPassPlain `
        -Domain $Domain

    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
    Write-Info ""
} else {
    Write-Info "STEP 6: Skipped NPM setup (-SkipNginx)"
    Write-Info ""
}

# Step 7: AdGuard DNS rewrites
if (-not $SkipDns) {
    Write-Info "STEP 7: AdGuard DNS rewrites"
    & "$ScriptRoot\setup-adguard-dns.ps1" -AdGuardUrl $AdGuardUrl -Domain $Domain
    Write-Info ""
} else {
    Write-Info "STEP 7: Skipped DNS setup (-SkipDns)"
    Write-Info ""
}

# Step 8: Restart Authelia to pick up config
Write-Info "STEP 8: Restarting Authelia"
Push-Location (Join-Path $ProjectRoot "infra-stack")
docker compose restart authelia 2>$null | Out-Null
Pop-Location
Write-Success "[+] Authelia restarted"
Write-Info ""

Write-Info "[====================================================]"
Write-Success "[           Setup complete!                          ]"
Write-Info "[====================================================]"
Write-Info ""
Write-Info "Try these URLs (after DNS propagates):"
Write-Info "  http://authelia.$Domain       — SSO login portal"
Write-Info "  http://sonarr.$Domain         — protected by Authelia"
Write-Info "  http://plex.$Domain           — protected by Authelia"
Write-Info "  http://homepage.$Domain       — dashboard"
Write-Info ""
Write-Info "Admin UIs:"
Write-Info "  NPM:     $NginxUrl  (change default password!)"
Write-Info "  AdGuard: $AdGuardUrl"
Write-Info ""
Write-Info "Re-run individual steps:"
Write-Info "  npm run setup:nginx"
Write-Info "  npm run setup:dns"
Write-Info "  npm run setup:authelia"
Write-Info ""
