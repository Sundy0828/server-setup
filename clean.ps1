# Clean up config and data folders from all stacks while preserving .env files

param(
    [switch]$Force
)

$stacks = @("adblock-stack", "homeassistant-stack", "plex-stack", "infra-stack", "minecraft-stack")

function Remove-DirectoryExceptEnv {
    param(
        [string]$Path
    )
    
    if (Test-Path $Path) {
        Write-Host "Cleaning: $Path"
        
        # Get all items in the directory
        $items = Get-ChildItem -Path $Path -Force
        
        foreach ($item in $items) {
            # Skip .env files
            if ($item.Name -eq ".env" -or $item.Name -eq ".env.local") {
                Write-Host "  Preserving: $($item.Name)"
                continue
            }
            
            # Remove the item
            if ($item.PSIsContainer) {
                Remove-Item -Path $item.FullName -Recurse -Force
                Write-Host "  Removed folder: $($item.Name)"
            } else {
                Remove-Item -Path $item.FullName -Force
                Write-Host "  Removed file: $($item.Name)"
            }
        }
    }
}

Write-Host "Starting cleanup of config and data folders..." -ForegroundColor Green

foreach ($stack in $stacks) {
    $configPath = Join-Path $stack "config"
    $dataPath = Join-Path $stack "data"
    
    if (Test-Path $configPath) {
        Remove-DirectoryExceptEnv -Path $configPath
    }
    
    if (Test-Path $dataPath) {
        Remove-DirectoryExceptEnv -Path $dataPath
    }
}

Write-Host "Cleanup complete!" -ForegroundColor Green
