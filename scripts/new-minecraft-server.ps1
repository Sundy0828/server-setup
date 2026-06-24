param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Name,
    [Parameter(Mandatory=$false)]
    [ValidateSet("paper-survival", "vanilla-survival", "vanilla-creative", "curseforge")]
    [string]$Type = "paper-survival",
    [Parameter(Mandatory=$false)]
    [int]$Port = 0
)

if (-not $Name) {
    Write-Host "Usage:"
    Write-Host "  npm run new:minecraft -- -Name <server-name> [-Type paper-survival|vanilla-survival|vanilla-creative|curseforge] [-Port 25565]"
    Write-Host ""
    Write-Host "Or via typed shortcuts:"
    Write-Host "  npm run new:minecraft:paper -- my-server"
    Write-Host "  npm run new:minecraft:vanilla -- my-server"
    Write-Host "  npm run new:minecraft:creative -- my-server"
    Write-Host "  npm run new:minecraft:curseforge -- my-server"
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$templatesDir = Join-Path $repoRoot "minecraft-stack\templates"
$serversDir = Join-Path $repoRoot "minecraft-stack\servers"
$templatePath = Join-Path $templatesDir $Type
$targetPath = Join-Path $serversDir $Name

if (-not (Test-Path $templatePath)) {
    Write-Error "Template '$Type' not found at $templatePath"
    exit 1
}

if (Test-Path $targetPath) {
    Write-Error "Server '$Name' already exists at minecraft-stack/servers/$Name"
    exit 1
}

Copy-Item -Recurse $templatePath $targetPath

$envExample = Join-Path $targetPath ".env.example"
$envFile = Join-Path $targetPath ".env"

if (Test-Path $envExample) {
    $content = Get-Content $envExample -Raw
    $content = $content -replace "MC_CONTAINER_NAME=.*", "MC_CONTAINER_NAME=minecraft-$Name"
    $content = $content -replace "PLAYIT_CONTAINER_NAME=.*", "PLAYIT_CONTAINER_NAME=playit-$Name"
    if ($Port -gt 0) {
        $content = $content -replace "MC_PORT=.*", "MC_PORT=$Port"
    }
    $content | Set-Content -Path $envFile -Encoding UTF8 -NoNewline
}

Write-Host ""
Write-Host "Created server '$Name' from template '$Type'"
Write-Host "  Path: minecraft-stack/servers/$Name"
Write-Host ""
if ($Type -eq "curseforge") {
    Write-Host "  Set CF_PAGE_URL and CF_API_KEY in .env, then:"
} else {
    Write-Host "  Edit .env if needed, then:"
}
Write-Host "    cd minecraft-stack/servers/$Name"
Write-Host "    docker compose up -d"
Write-Host ""
