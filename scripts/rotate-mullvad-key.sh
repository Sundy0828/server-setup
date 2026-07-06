#!/usr/bin/env bash
# Rotates the Mullvad WireGuard key:
#   1. Generates a new key pair locally
#   2. Deletes all existing Mullvad devices
#   3. Registers the new public key with Mullvad
#   4. Updates plex-stack/.env with the new private key + assigned IP
#   5. Restarts gluetun
#
# Usage: ./scripts/rotate-mullvad-key.sh --account-number <number> [options]

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: rotate-mullvad-key.sh --account-number <number> [options]

Options:
  --account-number <number>   Mullvad account number (required)
  --env-file <path>           Path to the .env file to update
                              (default: <repo>/plex-stack/.env)
  --device-name <name>        Name to log for the new device (default: gluetun-homelab)
  -h, --help                  Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACCOUNT_NUMBER=""
ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/plex-stack/.env"
DEVICE_NAME="gluetun-homelab"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-number) ACCOUNT_NUMBER="$2"; shift 2 ;;
    --account-number=*) ACCOUNT_NUMBER="${1#*=}"; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --env-file=*) ENV_FILE="${1#*=}"; shift ;;
    --device-name) DEVICE_NAME="$2"; shift 2 ;;
    --device-name=*) DEVICE_NAME="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$ACCOUNT_NUMBER" ]]; then
  echo "Error: --account-number is required" >&2
  usage
  exit 1
fi

# ── 1. Generate key pair ──────────────────────────────────────────────────────
echo "Generating WireGuard key pair..."

key_json="$(python3 -c '
import base64, json
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, PrivateFormat, NoEncryption

priv = X25519PrivateKey.generate()
pub  = priv.public_key()

print(json.dumps({
    "private": base64.b64encode(priv.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())).decode(),
    "public":  base64.b64encode(pub.public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
}))
')"

priv_key="$(printf '%s' "$key_json" | jq -r '.private')"
pub_key="$(printf '%s' "$key_json" | jq -r '.public')"
echo "  Public key: $pub_key"

# ── 2. Authenticate ───────────────────────────────────────────────────────────
echo "Authenticating with Mullvad..."

auth_body="$(jq -n --arg account_number "$ACCOUNT_NUMBER" '{account_number: $account_number}')"
auth_resp="$(curl -sS -X POST "https://api.mullvad.net/auth/v1/token" \
  -H "Content-Type: application/json" -d "$auth_body")"
token="$(printf '%s' "$auth_resp" | jq -r '.access_token')"

if [[ -z "$token" || "$token" == "null" ]]; then
  echo "Error: Mullvad authentication failed: $auth_resp" >&2
  exit 1
fi

# ── 3. Delete all existing devices ───────────────────────────────────────────
echo "Removing existing devices..."

devices="$(curl -sS -H "Authorization: Bearer $token" "https://api.mullvad.net/accounts/v1/devices")"
device_count="$(printf '%s' "$devices" | jq 'length')"

for (( i = 0; i < device_count; i++ )); do
  device_id="$(printf '%s' "$devices" | jq -r ".[$i].id")"
  device_name="$(printf '%s' "$devices" | jq -r ".[$i].name")"
  echo "  Deleting: $device_name ($device_id)"
  curl -sS -X DELETE -H "Authorization: Bearer $token" \
    "https://api.mullvad.net/accounts/v1/devices/$device_id" >/dev/null
done

# ── 4. Register new public key ────────────────────────────────────────────────
echo "Registering new public key as '$DEVICE_NAME'..."

reg_body="$(jq -n --arg pubkey "$pub_key" '{pubkey: $pubkey, hijack_dns: false}')"
new_device="$(curl -sS -X POST "https://api.mullvad.net/accounts/v1/devices" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d "$reg_body")"

ipv4="$(printf '%s' "$new_device" | jq -r '.ipv4_address')"
if [[ -z "$ipv4" || "$ipv4" == "null" ]]; then
  echo "Error: failed to register new device: $new_device" >&2
  exit 1
fi
echo "  Assigned IP: $ipv4"

# ── 5. Update .env ────────────────────────────────────────────────────────────
echo "Updating $ENV_FILE..."

if [[ -f "$ENV_FILE" ]]; then
  sed -i \
    -e "s#^WIREGUARD_PRIVATE_KEY=.*#WIREGUARD_PRIVATE_KEY=${priv_key}#" \
    -e "s#^WIREGUARD_ADDRESSES=.*#WIREGUARD_ADDRESSES=${ipv4}#" \
    "$ENV_FILE"
else
  echo "Warning: $ENV_FILE not found — nothing updated on disk" >&2
fi

# ── 6. Restart gluetun ───────────────────────────────────────────────────────
echo "Restarting gluetun..."
(cd "$(dirname "$ENV_FILE")" && docker compose up -d gluetun)

echo ""
echo "Done. New WireGuard config:"
echo "  Private key : $priv_key"
echo "  Public key  : $pub_key"
echo "  Address     : $ipv4"
