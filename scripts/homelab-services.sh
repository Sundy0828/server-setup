#!/usr/bin/env bash
# Shared service catalog for NPM proxy hosts and AdGuard DNS rewrites.
# Source from setup scripts: source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/homelab-services.sh"

HOMELAB_DEFAULT_HOST_IP="192.168.0.54"

# HOMELAB_SERVICES: one "name|host|port|ws|skipAuth|dns" string per service.
# ws / skipAuth / dns are "true" or "false".
HOMELAB_SERVICES=(
  "authelia|authelia|9091|false|true|true"
  "dashboard|homepage|3000|false|false|true"
  "uptime-kuma|uptime-kuma|3001|true|false|true"
  "duplicati|duplicati|8200|false|false|true"
  "adguard|adguardhome|80|false|false|true"
  "assistant|homeassistant|8123|true|false|true"
  "plex|plex|32400|false|false|true"
  "sonarr|sonarr|8989|false|false|true"
  "radarr|radarr|7878|false|false|true"
  "lidarr|lidarr|8686|false|false|true"
  "bazarr|bazarr|6767|false|false|true"
  "prowlarr|prowlarr|9696|false|false|true"
  "readarr|readarr|8787|false|false|true"
  "qbittorrent|gluetun|8080|false|false|true"
  "overseerr|overseerr|5055|false|false|true"
  "audiobookshelf|audiobookshelf|80|true|false|true"
  "nginx|nginx|81|false|false|true"
)

# read_dotenv_value <path> <key> [default]
# Prints the value assigned to KEY= in a simple .env file (first match wins).
read_dotenv_value() {
  local path="$1" key="$2" default="${3:-}"
  local line value

  if [[ ! -f "$path" ]]; then
    printf '%s\n' "$default"
    return 0
  fi

  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$path" | head -n1 || true)"
  if [[ -z "$line" ]]; then
    printf '%s\n' "$default"
    return 0
  fi

  value="${line#*=}"
  # Trim leading/trailing whitespace
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  printf '%s\n' "$value"
}

# get_homelab_host_ip [preferred_ip] [env_path]
get_homelab_host_ip() {
  local preferred_ip="${1:-}" env_path="${2:-}"
  local from_env

  if [[ -n "$preferred_ip" ]]; then
    printf '%s' "$preferred_ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    echo
    return 0
  fi

  if [[ -n "$env_path" ]]; then
    from_env="$(read_dotenv_value "$env_path" "HOMELAB_HOST_IP" "")"
    if [[ -n "$from_env" ]]; then
      printf '%s' "$from_env" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
      echo
      return 0
    fi
  fi

  printf '%s\n' "$HOMELAB_DEFAULT_HOST_IP"
}

# get_homelab_dns_domains [domain]
# Prints one "<name>.<domain>" per line, sorted and de-duplicated, for services
# with dns=true.
get_homelab_dns_domains() {
  local domain="${1:-home.lab}"
  local entry name dns
  local -a domains=()

  for entry in "${HOMELAB_SERVICES[@]}"; do
    IFS='|' read -r name _ _ _ _ dns <<< "$entry"
    if [[ "$dns" == "true" ]]; then
      domains+=("${name}.${domain}")
    fi
  done

  printf '%s\n' "${domains[@]}" | sort -u
}

# get_npm_proxy_host_list <json>
# Normalizes an NPM API response (a bare array or an {proxy_hosts:[...]}
# envelope) into a JSON array. Requires jq.
get_npm_proxy_host_list() {
  local raw="${1:-}"
  if [[ -z "$raw" || "$raw" == "null" ]]; then
    echo "[]"
    return 0
  fi
  printf '%s' "$raw" | jq -c 'if type == "array" then . elif has("proxy_hosts") then .proxy_hosts elif type == "object" then [.] else [.] end'
}

# get_proxy_host_domain_names <proxy_host_json>
# Prints each domain_names entry of a single proxy host object, one per line.
get_proxy_host_domain_names() {
  local proxy_host_json="${1:-}"
  [[ -z "$proxy_host_json" ]] && return 0
  printf '%s' "$proxy_host_json" | jq -r '(.domain_names // [])[]'
}
