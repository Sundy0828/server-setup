#!/usr/bin/env bash
# setup.sh — interactive .env setup for the plex stack
# Run this once before `docker compose up -d`
# Re-running is safe — already-set values are left alone.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
EXAMPLE_FILE="${SCRIPT_DIR}/.env.example"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_ok()   { echo -e "  ${GREEN}[ OK ]${NC} $*"; }
log_info() { echo -e "  ${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }

# Bootstrap .env from example if it doesn't exist
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$EXAMPLE_FILE" ]]; then
    cp "$EXAMPLE_FILE" "$ENV_FILE"
    log_info "Created .env from .env.example"
  else
    touch "$ENV_FILE"
    log_warn ".env.example not found — created empty .env"
  fi
fi

# Read current value of a key from .env (strips inline comments and whitespace)
get_env() {
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | sed "s/^$1=//" | sed 's/[[:space:]]*#.*//' | tr -d '\r '
}

# Set or replace a key in .env
set_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

# Prompt for a value only if the current value is blank/placeholder
# $1=key  $2=prompt  $3=hint  $4=secret(0/1)  $5=placeholder_pattern(optional)
prompt_if_blank() {
  local key="$1" prompt_text="$2" hint="${3:-}" secret="${4:-0}" placeholder="${5:-}"
  local current
  current=$(get_env "$key")

  # Treat known placeholder patterns as blank
  if [[ -n "$placeholder" && "$current" =~ $placeholder ]]; then
    current=""
  fi

  if [[ -n "$current" ]]; then
    if [[ "$secret" == "1" ]]; then
      log_ok "${key} = ****"
    else
      log_ok "${key} = ${current}"
    fi
    return
  fi

  echo ""
  echo -e "  ${CYAN}${key}${NC}: ${prompt_text}"
  [[ -n "$hint" ]] && echo -e "    ${YELLOW}↳ ${hint}${NC}"
  local value
  if [[ "$secret" == "1" ]]; then
    read -rsp "    > " value; echo
  else
    read -rp "    > " value
  fi

  if [[ -n "$value" ]]; then
    set_env "$key" "$value"
    log_ok "${key} saved"
  else
    log_warn "${key} left blank — skipped (you can re-run setup.sh later)"
  fi
}

echo -e "\n${BOLD}${CYAN}── Plex Stack Environment Setup ──${NC}\n"
echo -e "  Checking ${ENV_FILE}\n"

# ── Core ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Core settings${NC}"
prompt_if_blank "DATA_PATH" \
  "Path to your media/data directory on the host" \
  "e.g. ./data  or  /mnt/media  — must contain downloads/ and media/ subdirs"

prompt_if_blank "PLEX_CLAIM" \
  "Plex claim token for first-time server registration" \
  "Get one at https://www.plex.tv/claim/  (expires in 4 minutes)"

# ── VPN ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}VPN (WireGuard / Gluetun)${NC} — only needed if you uncomment gluetun in compose.yml"
prompt_if_blank "WIREGUARD_PRIVATE_KEY" \
  "WireGuard private key from your Mullvad/VPN config" \
  "Leave blank to skip — gluetun is disabled by default" "1"

prompt_if_blank "WIREGUARD_ADDRESSES" \
  "WireGuard assigned IP address (e.g. 10.66.x.x/32)" \
  "Leave blank to skip" "0" "^10\\.x\\.x\\.x"

# ── Tailscale ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Tailscale${NC} — for remote Overseerr access"
prompt_if_blank "TS_AUTHKEY" \
  "Tailscale auth key for the Overseerr sidecar" \
  "Get one at tailscale.com/admin/settings/keys  — leave blank to skip" "1"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}Setup complete!${NC} .env is ready.\n"

MISSING=()
[[ -z "$(get_env WIREGUARD_PRIVATE_KEY)" ]] && MISSING+=("WIREGUARD_PRIVATE_KEY (VPN disabled — OK if not using gluetun)")
[[ -z "$(get_env TS_AUTHKEY)" ]]            && MISSING+=("TS_AUTHKEY (Tailscale disabled — OK if not using remote access)")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo -e "  ${YELLOW}Optional items not set:${NC}"
  for m in "${MISSING[@]}"; do echo -e "    • ${m}"; done
  echo ""
fi

echo -e "  Next steps:"
echo -e "    1. ${CYAN}docker compose up -d${NC}"
echo -e "    2. Wait ~30 seconds for services to initialize"
echo -e "    3. ${CYAN}./arr-setup.sh${NC}  (configures Sonarr/Radarr/Prowlarr/etc.)"
echo ""
