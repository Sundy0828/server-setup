# Authelia Configuration Setup Script
# Generates secrets and password hashes, updates .env and users_database.yml

param(
    [switch]$SkipSecrets,
    [switch]$SkipUsers,
    [string]$Domain = "home.lab"
)

$ErrorActionPreference = "Stop"

# Color output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
$AutheliaPath = Join-Path $ProjectRoot "infra-stack\helper-setup\authelia"
$EnvPath = Join-Path $ProjectRoot "infra-stack\.env"
$ConfigDir = Join-Path $ProjectRoot "infra-stack\config\authelia"
$UsersDbPath = Join-Path $ConfigDir "users_database.yml"
$ConfigPath = Join-Path $ConfigDir "configuration.yml"
$TemplateDir = Join-Path $ProjectRoot "infra-stack\templates\authelia"

Write-Info "[====================================================]"
Write-Info "[    Authelia Configuration Setup                    ]"
Write-Info "[===================================================="]
Write-Info "Domain: $Domain"
Write-Info ""

if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

if (-not (Test-Path $ConfigPath) -and (Test-Path (Join-Path $TemplateDir "configuration.yml.example"))) {
    $template = Get-Content (Join-Path $TemplateDir "configuration.yml.example") -Raw
    $template.Replace("{{DOMAIN}}", $Domain) | Set-Content $ConfigPath -NoNewline
    Write-Success '[OK] Created configuration.yml from template'
}

if (-not (Test-Path $UsersDbPath) -and (Test-Path (Join-Path $TemplateDir "users_database.yml.example"))) {
    Copy-Item (Join-Path $TemplateDir "users_database.yml.example") $UsersDbPath
    Write-Success '[OK] Created users_database.yml from template'
}

$notifyPath = Join-Path $ConfigDir "notification.txt"
if (-not (Test-Path $notifyPath)) {
    "" | Set-Content $notifyPath
}

Write-Info ""

# Step 1: Generate Secrets
if (-not $SkipSecrets) {
    Write-Info "STEP 1: Generating Secrets..."
    Write-Info "Executing: generate-secrets.bat"
    Write-Info ""
    
    $secretsBatPath = Join-Path $AutheliaPath "generate-secrets.bat"
    Write-Info "Using path: $secretsBatPath"
    $secretsOutput = & cmd /c "`"$secretsBatPath`"" 2>&1
    
    Write-Info "Generated secrets output:"
    Write-Info $secretsOutput
    Write-Info ""
    
    # Parse the output to extract secrets
    $jwtSecret = $null
    $sessionSecret = $null
    $encryptionKey = $null
    
    $lines = $secretsOutput -split "`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match "JWT_SECRET") {
            # Secret value is on the next line
            if ($i + 1 -lt $lines.Length) {
                $jwtSecret = $lines[$i + 1].Trim()
            }
        }
        elseif ($line -match "SESSION_SECRET") {
            # Secret value is on the next line
            if ($i + 1 -lt $lines.Length) {
                $sessionSecret = $lines[$i + 1].Trim()
            }
        }
        elseif ($line -match "STORAGE_ENCRYPTION_KEY") {
            # Secret value is on the next line
            if ($i + 1 -lt $lines.Length) {
                $encryptionKey = $lines[$i + 1].Trim()
            }
        }
    }
    
    if (-not $jwtSecret -or -not $sessionSecret -or -not $encryptionKey) {
        Write-Error "Failed to parse secrets from generate-secrets.bat output"
        Write-Info "Raw output was:"
        Write-Info $secretsOutput
        exit 1
    }
    
    # Update .env file
    Write-Info "Updating .env file..."
    
    # Read existing .env or create new
    $envContent = if (Test-Path $EnvPath) { Get-Content $EnvPath -Raw } else { "" }
    
    # Update or add each secret
    if ($envContent -match "AUTHELIA_JWT_SECRET=") {
        $envContent = $envContent -replace "AUTHELIA_JWT_SECRET=.*", "AUTHELIA_JWT_SECRET=$jwtSecret"
    } else {
        $envContent += "`nAUTHELIA_JWT_SECRET=$jwtSecret"
    }
    
    if ($envContent -match "AUTHELIA_SESSION_SECRET=") {
        $envContent = $envContent -replace "AUTHELIA_SESSION_SECRET=.*", "AUTHELIA_SESSION_SECRET=$sessionSecret"
    } else {
        $envContent += "`nAUTHELIA_SESSION_SECRET=$sessionSecret"
    }
    
    if ($envContent -match "AUTHELIA_STORAGE_ENCRYPTION_KEY=") {
        $envContent = $envContent -replace "AUTHELIA_STORAGE_ENCRYPTION_KEY=.*", "AUTHELIA_STORAGE_ENCRYPTION_KEY=$encryptionKey"
    } else {
        $envContent += "`nAUTHELIA_STORAGE_ENCRYPTION_KEY=$encryptionKey"
    }
    
    $envContent | Set-Content $EnvPath
    Write-Success '[OK] .env file updated with secrets'
    Write-Info ""
}

# Step 2: Generate User Passwords
if (-not $SkipUsers) {
    Write-Info "STEP 2: Generating User Passwords..."
    Write-Info ""
    
    # Define users to set up
    $users = @(
        @{
            Username = "admin"
            DisplayName = "Administrator"
            Email = "jerrod.sunderland@gmail.com"
        }
    )
    
    $userHashes = @{}
    
    foreach ($user in $users) {
        Write-Info "Setting up user: $($user.Username)"
        
        # Prompt for password
        $securePass = Read-Host "  Enter password for $($user.Username)" -AsSecureString
        $plainPass = [System.Net.NetworkCredential]::new("", $securePass).Password
        
        # Generate hash
        Write-Info "  Generating password hash..."
        $hashBatPath = Join-Path $AutheliaPath "generate-hash.bat"
        $hashOutput = & cmd /c "`"$hashBatPath`" $plainPass" 2>&1
        
        # Extract hash (last line usually contains it)
        $hash = ($hashOutput -split "`n" | Where-Object { $_ -match '\$argon2' } | Select-Object -Last 1).Trim()
        
        # Remove "Digest: " prefix if present
        $hash = $hash -replace '^Digest:\s*', ''
        
        if (-not $hash) {
            Write-Error "Failed to generate hash for user $($user.Username)"
            exit 1
        }
        
        $userHashes[$user.Username] = @{
            DisplayName = $user.DisplayName
            Email = $user.Email
            Hash = $hash
        }
        
        Write-Success '  [OK] Password hash generated'
        Write-Info ""
    }
    
    # Update users_database.yml
    Write-Info "Updating users_database.yml..."
    
    $usersYaml = "###############################################################################`r`n"
    $usersYaml += "#                           Users Database                                    #`r`n"
    $usersYaml += "###############################################################################`r`n`r`n"
    $usersYaml += "users:`r`n"
    
    foreach ($username in $userHashes.Keys) {
        $user = $userHashes[$username]
        $displayName = $user.DisplayName
        $hash = $user.Hash
        $email = $user.Email
        
        $usersYaml += "`r`n"
        $usersYaml += "  $username :`r`n"
        $usersYaml += "    displayname : `"$displayName`"`r`n"
        $usersYaml += "    password : `"$hash`"`r`n"
        $usersYaml += "    email : $email`r`n"
        $usersYaml += "    groups:`r`n"
        $usersYaml += "      - users`r`n"
    }
    
    $usersYaml | Set-Content $UsersDbPath
    Write-Success '[OK] users_database.yml updated'
    Write-Info ""
}

# Summary
Write-Info "[===================================================="]
Write-Success "[    Setup Complete!                                  ]"
Write-Info "[===================================================="]
Write-Info ""

if (-not $SkipSecrets) {
    Write-Success '[OK] Secrets generated and added to infra-stack\.env'
    Write-Info "  - AUTHELIA_JWT_SECRET"
    Write-Info "  - AUTHELIA_SESSION_SECRET"
    Write-Info "  - AUTHELIA_STORAGE_ENCRYPTION_KEY"
    Write-Info ""
}

if (-not $SkipUsers) {
    Write-Success '[OK] User passwords hashed and added to users_database.yml'
    Write-Info "  - admin"
    Write-Info "  - reg"
    Write-Info ""
}

Write-Info "[NEXT] Next Steps:"
Write-Info "  1. Run full bootstrap: npm run setup"
Write-Info "  2. Or start stacks:    npm run start:all"
Write-Info "  3. Configure NPM/DNS:   npm run setup:nginx && npm run setup:dns"
Write-Info ""

Write-Success "Done!"
