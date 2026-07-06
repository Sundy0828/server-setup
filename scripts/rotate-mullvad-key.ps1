# Rotates the Mullvad WireGuard key:
#   1. Generates a new key pair locally
#   2. Deletes all existing Mullvad devices
#   3. Registers the new public key with Mullvad
#   4. Updates plex-stack/.env with the new private key + assigned IP
#   5. Restarts gluetun

param(
    [Parameter(Mandatory=$true)]
    [string]$AccountNumber,

    [string]$EnvFile = "$PSScriptRoot\..\plex-stack\.env",
    [string]$DeviceName = "gluetun-homelab"
)

$ErrorActionPreference = "Stop"

# ── 1. Generate key pair ──────────────────────────────────────────────────────
Write-Host "Generating WireGuard key pair..."

$keyJson = python -c @"
import base64, json, os
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, PrivateFormat, NoEncryption

priv = X25519PrivateKey.generate()
pub  = priv.public_key()

print(json.dumps({
    'private': base64.b64encode(priv.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())).decode(),
    'public':  base64.b64encode(pub.public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
}))
"@

$keys     = $keyJson | ConvertFrom-Json
$privKey  = $keys.private
$pubKey   = $keys.public
Write-Host "  Public key: $pubKey"

# ── 2. Authenticate ───────────────────────────────────────────────────────────
Write-Host "Authenticating with Mullvad..."

$authBody = @{ account_number = $AccountNumber } | ConvertTo-Json
$authResp = Invoke-RestMethod -Uri "https://api.mullvad.net/auth/v1/token" `
    -Method POST -Body $authBody -ContentType "application/json"
$token   = $authResp.access_token
$headers = @{ Authorization = "Bearer $token" }

# ── 3. Delete all existing devices ───────────────────────────────────────────
Write-Host "Removing existing devices..."

$devices = Invoke-RestMethod -Uri "https://api.mullvad.net/accounts/v1/devices" -Headers $headers
foreach ($device in $devices) {
    Write-Host "  Deleting: $($device.name) ($($device.id))"
    Invoke-RestMethod -Uri "https://api.mullvad.net/accounts/v1/devices/$($device.id)" `
        -Method DELETE -Headers $headers | Out-Null
}

# ── 4. Register new public key ────────────────────────────────────────────────
Write-Host "Registering new public key as '$DeviceName'..."

$regBody    = @{ pubkey = $pubKey; hijack_dns = $false } | ConvertTo-Json
$newDevice  = Invoke-RestMethod -Uri "https://api.mullvad.net/accounts/v1/devices" `
    -Method POST -Body $regBody -ContentType "application/json" -Headers $headers

$ipv4 = $newDevice.ipv4_address
Write-Host "  Assigned IP: $ipv4"

# ── 5. Update .env ────────────────────────────────────────────────────────────
Write-Host "Updating $EnvFile..."

$env = Get-Content $EnvFile -Raw
$env = $env -replace 'WIREGUARD_PRIVATE_KEY=.*', "WIREGUARD_PRIVATE_KEY=$privKey"
$env = $env -replace 'WIREGUARD_ADDRESSES=.*',   "WIREGUARD_ADDRESSES=$ipv4"
Set-Content $EnvFile $env -NoNewline

# ── 6. Restart gluetun ───────────────────────────────────────────────────────
Write-Host "Restarting gluetun..."
Push-Location (Split-Path $EnvFile)
docker compose up -d gluetun
Pop-Location

Write-Host ""
Write-Host "Done. New WireGuard config:"
Write-Host "  Private key : $privKey"
Write-Host "  Public key  : $pubKey"
Write-Host "  Address     : $ipv4"
