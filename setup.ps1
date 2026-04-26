# Setup script for homelab environment
# Creates Docker network and initializes configuration

param(
    [switch]$Force
)

Write-Host "🏠 Initializing Homelab Environment..." -ForegroundColor Cyan

# Create homelab network if it doesn't exist
Write-Host "`n📡 Setting up Docker network..." -ForegroundColor Yellow
$networkExists = docker network ls --filter name=homelab --quiet
if ($networkExists) {
    Write-Host "✓ Network 'homelab' already exists" -ForegroundColor Green
} else {
    Write-Host "Creating network 'homelab'..." -ForegroundColor Gray
    docker network create homelab
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Network 'homelab' created" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to create network" -ForegroundColor Red
        exit 1
    }
}

# Setup Homepage configuration
Write-Host "`n📋 Setting up Homepage configuration..." -ForegroundColor Yellow
$homepageExampleDir = "$PSScriptRoot\infra-stack\yaml-config\homepage"
$homepageRuntimeDir = "$PSScriptRoot\infra-stack\config\homepage"

if (Test-Path $homepageExampleDir) {
    # Create runtime directory if it doesn't exist
    if (!(Test-Path $homepageRuntimeDir)) {
        New-Item -ItemType Directory -Path $homepageRuntimeDir -Force | Out-Null
        Write-Host "✓ Created Homepage config directory" -ForegroundColor Green
    }
    
    # Copy files if not already there or if Force flag is set
    $files = Get-ChildItem -Path $homepageExampleDir -File
    foreach ($file in $files) {
        $targetPath = Join-Path $homepageRuntimeDir $file.Name
        if (!(Test-Path $targetPath) -or $Force) {
            Copy-Item -Path $file.FullName -Destination $targetPath -Force
            Write-Host "✓ Copied $($file.Name)" -ForegroundColor Green
        } else {
            Write-Host "⊘ $($file.Name) already exists (use -Force to overwrite)" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "⚠ Example config not found at $homepageExampleDir" -ForegroundColor Yellow
}

Write-Host "`n✓ Setup complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  • Fill in .env files with your configuration"
Write-Host "  • Run 'npm run start:all' to start all services"
Write-Host "  • Access Homepage at http://localhost:3000"
