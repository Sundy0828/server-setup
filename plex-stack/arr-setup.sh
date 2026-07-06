#!/usr/bin/env bash
# arr-setup.sh
# Automates initial configuration of the *arr stack after `docker compose up -d`.
#
# Usage:
#   ./arr-setup.sh
#
# Optional env overrides (or create arr-setup.env in this directory):
#   QB_PASSWORD=...          qBittorrent web UI password
#   SONARR_URL=...           default: http://localhost:8989
#   TV_PATH=...              default: /data/media/tv
#   etc.
#
# Prerequisites:
#   - Stack started with `docker compose up -d` and services have initialized
#     (config XML files must exist — run at least 30s after compose up)
#   - jq installed for media management patching (optional but recommended)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"

# ── Optional override file (not committed) ───────────────────────────────────
[[ -f "${SCRIPT_DIR}/arr-setup.env" ]] && source "${SCRIPT_DIR}/arr-setup.env"

# ── Service URLs (host-side, for this script's API calls) ────────────────────
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
LIDARR_URL="${LIDARR_URL:-http://localhost:8686}"
READARR_URL="${READARR_URL:-http://localhost:8787}"
PROWLARR_URL="${PROWLARR_URL:-http://localhost:9696}"
BAZARR_URL="${BAZARR_URL:-http://localhost:6767}"

# ── Container names (used in inter-service config values on the Docker network)
SONARR_HOST="${SONARR_HOST:-sonarr}"
RADARR_HOST="${RADARR_HOST:-radarr}"
LIDARR_HOST="${LIDARR_HOST:-lidarr}"
READARR_HOST="${READARR_HOST:-readarr}"
PROWLARR_HOST="${PROWLARR_HOST:-prowlarr}"
# qbittorrent uses network_mode: service:gluetun in compose.yml, so it has no
# DNS name of its own on the homelab network — other containers must reach it
# via gluetun's hostname.
QBIT_HOST="${QBIT_HOST:-gluetun}"
FLARESOLVERR_HOST="${FLARESOLVERR_HOST:-flaresolverr}"

# ── qBittorrent credentials ───────────────────────────────────────────────────
QB_USERNAME="${QB_USERNAME:-admin}"
QB_PASSWORD="${QB_PASSWORD:-}"

# ── Rutracker credentials (optional — set in arr-setup.env to auto-add) ──────
RUTRACKER_USER="${RUTRACKER_USER:-}"
RUTRACKER_PASS="${RUTRACKER_PASS:-}"

# ── Media paths (inside containers) ──────────────────────────────────────────
TV_PATH="${TV_PATH:-/data/media/tv}"
MOVIES_PATH="${MOVIES_PATH:-/data/media/movies}"
MUSIC_PATH="${MUSIC_PATH:-/data/media/music}"
BOOKS_PATH="${BOOKS_PATH:-/data/media/books}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }
log_info()    { echo -e "  ${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "  ${GREEN}[ OK ]${NC} $*"; }
log_skip()    { echo -e "  ${YELLOW}[SKIP]${NC} $*"; }
log_warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
log_err()     { echo -e "  ${RED}[ERR ]${NC} $*" >&2; }
die()         { log_err "$*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# API helpers
# ─────────────────────────────────────────────────────────────────────────────

extract_xml_api_key() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  sed -n 's|.*<ApiKey>\([^<]*\)</ApiKey>.*|\1|p' "$file" 2>/dev/null | head -1 | tr -d '\r' || return 1
}

# Bazarr stores its config in YAML or INI depending on version
extract_bazarr_api_key() {
  local yaml="${CONFIG_DIR}/bazarr/config/config.yaml"
  local ini="${CONFIG_DIR}/bazarr/config/config.ini"
  if [[ -f "$yaml" ]]; then
    sed -n 's/.*apikey:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$yaml" 2>/dev/null | head -1 | tr -d '\r' || true
  elif [[ -f "$ini" ]]; then
    sed -n 's/.*apikey[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$ini" 2>/dev/null | head -1 | tr -d '\r' || true
  fi
}

wait_for_arr_service() {
  local name="$1" url="$2" key="$3" api_ver="${4:-v3}" max=30 n=0
  log_info "Waiting for ${name}..."
  while (( n++ < max )); do
    if curl -sf --max-time 3 -H "X-Api-Key: ${key}" "${url}/api/${api_ver}/system/status" &>/dev/null; then
      log_ok "${name} is ready"
      return 0
    fi
    sleep 2
  done
  log_warn "${name} did not respond in $((max * 2))s — will skip"
  return 1
}

wait_for_prowlarr() {
  local max=30 n=0
  log_info "Waiting for Prowlarr..."
  while (( n++ < max )); do
    if curl -sf --max-time 3 -H "X-Api-Key: ${PROWLARR_KEY}" \
        "${PROWLARR_URL}/api/v1/system/status" &>/dev/null; then
      log_ok "Prowlarr is ready"
      return 0
    fi
    sleep 2
  done
  log_warn "Prowlarr did not respond — will skip"
  return 1
}

wait_for_bazarr() {
  local max=30 n=0
  log_info "Waiting for Bazarr..."
  while (( n++ < max )); do
    if curl -sf --max-time 3 -H "X-Api-Key: ${BAZARR_KEY}" \
        "${BAZARR_URL}/api/system/status" &>/dev/null; then
      log_ok "Bazarr is ready"
      return 0
    fi
    sleep 2
  done
  log_warn "Bazarr did not respond — will skip"
  return 1
}

arr_get() {
  local url="$1" key="$2" endpoint="$3" ver="${4:-v3}"
  curl -sf -H "X-Api-Key: ${key}" "${url}/api/${ver}${endpoint}"
}

arr_post() {
  local url="$1" key="$2" endpoint="$3" body="$4" ver="${5:-v3}"
  curl -sf -X POST -H "X-Api-Key: ${key}" -H "Content-Type: application/json" \
    -d "${body}" "${url}/api/${ver}${endpoint}"
}

arr_put() {
  local url="$1" key="$2" endpoint="$3" body="$4" ver="${5:-v3}"
  curl -sf -X PUT -H "X-Api-Key: ${key}" -H "Content-Type: application/json" \
    -d "${body}" "${url}/api/${ver}${endpoint}"
}

prowlarr_get()  { curl -sf -H "X-Api-Key: ${PROWLARR_KEY}" "${PROWLARR_URL}/api/v1$1"; }
prowlarr_post() {
  curl -sf -X POST -H "X-Api-Key: ${PROWLARR_KEY}" -H "Content-Type: application/json" \
    -d "$2" "${PROWLARR_URL}/api/v1$1"
}

# Check if a name already exists in a JSON array (simple grep, avoids jq dependency)
name_exists() { echo "$1" | tr -d ' \t' | grep -q "\"name\":\"$2\""; }

# ─────────────────────────────────────────────────────────────────────────────
# Download client payload builder
# $1 = category field name  (tvCategory | movieCategory | musicCategory | bookCategory)
# $2 = category value       (tv-sonarr | movies-radarr | ...)
# ─────────────────────────────────────────────────────────────────────────────
qbit_json() {
  local cat_field="$1" cat_value="$2"
  cat <<EOF
{
  "name": "qBittorrent",
  "enable": true,
  "protocol": "torrent",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "implementationName": "qBittorrent",
  "implementation": "QBittorrent",
  "configContract": "QBittorrentSettings",
  "tags": [],
  "fields": [
    {"name": "host",             "value": "${QBIT_HOST}"},
    {"name": "port",             "value": 8080},
    {"name": "useSsl",           "value": false},
    {"name": "urlBase",          "value": ""},
    {"name": "username",         "value": "${QB_USERNAME}"},
    {"name": "password",         "value": "${QB_PASSWORD}"},
    {"name": "${cat_field}",     "value": "${cat_value}"},
    {"name": "recentTvPriority", "value": 0},
    {"name": "olderTvPriority",  "value": 0},
    {"name": "initialState",     "value": 0},
    {"name": "sequentialOrder",  "value": false},
    {"name": "firstAndLast",     "value": false},
    {"name": "contentLayout",    "value": 0}
  ]
}
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Configure a single arr app (Sonarr / Radarr / Lidarr / Readarr)
# $1=app_name  $2=url  $3=api_key  $4=root_path
# $5=qbit_category_field  $6=qbit_category_value  $7=api_version (default v3)
# $8=root_folder_display_name (required for v1 apps — Lidarr/Readarr)
# ─────────────────────────────────────────────────────────────────────────────
configure_arr() {
  local name="$1" url="$2" key="$3" root_path="$4" cat_field="$5" cat_value="$6" \
        ver="${7:-v3}" folder_name="${8:-}"

  # Root folder
  local roots
  roots=$(arr_get "$url" "$key" "/rootfolder" "$ver") || { log_warn "${name}: failed to fetch root folders"; return; }
  if echo "$roots" | grep -q "\"${root_path}\""; then
    log_skip "${name}: root folder already set (${root_path})"
  else
    local body
    if [[ "$ver" == "v1" && -n "$folder_name" ]] && command -v jq &>/dev/null; then
      # Lidarr/Readarr require Name + default profile IDs
      local qp_id mp_id
      qp_id=$(arr_get "$url" "$key" "/qualityprofile" "$ver" | jq -r '.[0].id // 1')
      mp_id=$(arr_get "$url" "$key" "/metadataprofile" "$ver" | jq -r '.[0].id // 1')
      body="{\"name\":\"${folder_name}\",\"path\":\"${root_path}\",\"defaultQualityProfileId\":${qp_id},\"defaultMetadataProfileId\":${mp_id}}"
    else
      body="{\"path\":\"${root_path}\"}"
    fi
    if arr_post "$url" "$key" "/rootfolder" "$body" "$ver" >/dev/null; then
      log_ok "${name}: root folder added → ${root_path}"
    else
      log_warn "${name}: root folder POST failed — path may not exist or is not writable"
    fi
  fi

  # qBittorrent download client
  local clients
  clients=$(arr_get "$url" "$key" "/downloadclient" "$ver") || { log_warn "${name}: failed to fetch download clients"; return; }
  if name_exists "$clients" "qBittorrent"; then
    log_skip "${name}: qBittorrent already configured"
  elif [[ -z "$QB_PASSWORD" ]]; then
    log_warn "${name}: QB_PASSWORD not set — skipping download client"
    log_warn "  Set QB_PASSWORD in arr-setup.env and re-run"
  else
    if arr_post "$url" "$key" "/downloadclient" "$(qbit_json "$cat_field" "$cat_value")" "$ver" >/dev/null; then
      log_ok "${name}: qBittorrent download client added (category: ${cat_value})"
    else
      log_warn "${name}: qBittorrent download client POST failed"
      log_warn "  If using qBittorrent 5.x: add manually in ${name} UI (known compat issue)"
      log_warn "  Host: ${QBIT_HOST}  Port: 8080  User: ${QB_USERNAME}  Pass: <QB_PASSWORD>"
    fi
  fi

  # Media management — enable hardlinks, delete empty folders, import extras
  local current
  current=$(arr_get "$url" "$key" "/config/mediamanagement" "$ver") || { log_warn "${name}: failed to fetch media management config"; return; }

  if command -v jq &>/dev/null; then
    local updated
    updated=$(echo "$current" | jq '
      .copyUsingHardlinks       = true  |
      .deleteEmptyFolders       = true  |
      .importExtraFiles         = true  |
      .extraFileExtensions      = "srt,nfo" |
      .createEmptySeriesFolders = false |
      .enableMediaInfo          = true
    ')
    if arr_put "$url" "$key" "/config/mediamanagement" "$updated" "$ver" >/dev/null; then
      log_ok "${name}: media management — hardlinks ✓, delete empty folders ✓, import extras ✓"
    else
      log_warn "${name}: media management PUT failed"
    fi
  else
    log_warn "${name}: jq not found — media management not patched (install jq to automate this)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Prowlarr: add FlareSolverr proxy
# ─────────────────────────────────────────────────────────────────────────────
setup_flaresolverr() {
  local proxies
  proxies=$(prowlarr_get "/indexerproxy")
  if echo "$proxies" | grep -qi "flaresolverr"; then
    log_skip "Prowlarr: FlareSolverr proxy already exists"
    return
  fi
  prowlarr_post "/indexerproxy" "$(cat <<EOF
{
  "name": "FlareSolverr",
  "implementationName": "FlareSolverr",
  "implementation": "FlareSolverr",
  "configContract": "FlareSolverrSettings",
  "tags": [],
  "fields": [
    {"name": "host",           "value": "http://${FLARESOLVERR_HOST}:8191"},
    {"name": "requestTimeout", "value": 60}
  ]
}
EOF
)" >/dev/null
  log_ok "Prowlarr: FlareSolverr proxy added (http://${FLARESOLVERR_HOST}:8191)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Prowlarr: add an arr app so indexers sync to it
# $1=impl  $2=configContract  $3=host  $4=port  $5=app_api_key  $6=sync_categories_json
# ─────────────────────────────────────────────────────────────────────────────
add_prowlarr_app() {
  local impl="$1" contract="$2" host="$3" port="$4" app_key="$5" cats="$6"
  local apps
  apps=$(prowlarr_get "/applications")
  if name_exists "$apps" "$impl"; then
    log_skip "Prowlarr: ${impl} already linked"
    return
  fi
  prowlarr_post "/applications" "$(cat <<EOF
{
  "name": "${impl}",
  "syncLevel": "fullSync",
  "implementationName": "${impl}",
  "implementation": "${impl}",
  "configContract": "${contract}",
  "tags": [],
  "fields": [
    {"name": "prowlarrUrl",           "value": "http://${PROWLARR_HOST}:9696"},
    {"name": "baseUrl",               "value": "http://${host}:${port}"},
    {"name": "apiKey",                "value": "${app_key}"},
    {"name": "syncCategories",        "value": ${cats}},
    {"name": "syncAnimeStandardFormat","value": false}
  ]
}
EOF
)" >/dev/null
  log_ok "Prowlarr: ${impl} linked (full sync)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Bazarr: connect to Sonarr and Radarr
# ─────────────────────────────────────────────────────────────────────────────
configure_bazarr() {
  local settings
  settings=$(curl -sf "${BAZARR_URL}/api/system/settings" -H "X-Api-Key: ${BAZARR_KEY}")

  # Sonarr
  if echo "$settings" | grep -q '"sonarr"' && \
     echo "$settings" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('sonarr',{}).get('enabled') else 1)" 2>/dev/null; then
    log_skip "Bazarr: Sonarr already configured"
  else
    curl -sf -X POST "${BAZARR_URL}/api/system/settings" \
      -H "X-Api-Key: ${BAZARR_KEY}" -H "Content-Type: application/json" \
      -d "$(cat <<EOF
{
  "sonarr": {
    "enabled": true,
    "ip": "${SONARR_HOST}",
    "port": 8989,
    "baseUrl": "/",
    "ssl": false,
    "apikey": "${SONARR_KEY}"
  }
}
EOF
)" >/dev/null
    log_ok "Bazarr: Sonarr connection configured"
  fi

  # Radarr
  if echo "$settings" | grep -q '"radarr"' && \
     echo "$settings" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('radarr',{}).get('enabled') else 1)" 2>/dev/null; then
    log_skip "Bazarr: Radarr already configured"
  else
    curl -sf -X POST "${BAZARR_URL}/api/system/settings" \
      -H "X-Api-Key: ${BAZARR_KEY}" -H "Content-Type: application/json" \
      -d "$(cat <<EOF
{
  "radarr": {
    "enabled": true,
    "ip": "${RADARR_HOST}",
    "port": 7878,
    "baseUrl": "/",
    "ssl": false,
    "apikey": "${RADARR_KEY}"
  }
}
EOF
)" >/dev/null
    log_ok "Bazarr: Radarr connection configured"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Prowlarr: add qBittorrent as a download client (for manual grabs in Prowlarr UI)
# ─────────────────────────────────────────────────────────────────────────────
add_prowlarr_downloadclient() {
  local clients
  clients=$(prowlarr_get "/downloadclient") || { log_warn "Prowlarr: failed to fetch download clients"; return; }
  if name_exists "$clients" "qBittorrent"; then
    log_skip "Prowlarr: qBittorrent download client already configured"
    return
  fi
  if [[ -z "$QB_PASSWORD" ]]; then
    log_warn "Prowlarr: QB_PASSWORD not set — skipping download client"
    return
  fi
  if ! command -v jq &>/dev/null; then
    log_warn "Prowlarr: jq required to add download client"
    return
  fi

  # Fetch the schema and patch only the fields we need; this preserves null defaults
  # (urlBase=null, apiKey=null) that Prowlarr requires — hardcoding them causes a null-ref error
  local schema payload
  schema=$(prowlarr_get "/downloadclient/schema" | jq '.[] | select(.implementation == "QBittorrent")') || {
    log_warn "Prowlarr: failed to fetch download client schema"
    return
  }
  payload=$(echo "$schema" | jq \
    --arg host "$QBIT_HOST" \
    --arg user "$QB_USERNAME" \
    --arg pass "$QB_PASSWORD" '
    .name = "qBittorrent" |
    .enable = true |
    .priority = 1 |
    .removeCompletedDownloads = true |
    .removeFailedDownloads = true |
    .fields = (.fields | map(
      if   .name == "host"     then .value = $host
      elif .name == "username" then .value = $user
      elif .name == "password" then .value = $pass
      elif .name == "category" then .value = "prowlarr"
      else .
      end
    ))
  ')

  if prowlarr_post "/downloadclient" "$payload" >/dev/null; then
    log_ok "Prowlarr: qBittorrent download client added"
  else
    log_warn "Prowlarr: qBittorrent download client POST failed"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Prowlarr: add public indexers from Cardigann library
# ─────────────────────────────────────────────────────────────────────────────
setup_prowlarr_indexers() {
  if ! command -v jq &>/dev/null; then
    log_warn "jq not found — skipping automatic indexer setup (install jq to automate this)"
    return
  fi

  local existing all_schemas app_profile_id flare_tag_id=""
  existing=$(prowlarr_get "/indexer") || { log_warn "Prowlarr: failed to list indexers"; return; }
  all_schemas=$(prowlarr_get "/indexer/schema") || { log_warn "Prowlarr: failed to fetch indexer schemas"; return; }
  # Prowlarr requires appProfileId > 0; fetch the first available profile (usually id=1 "Standard")
  app_profile_id=$(prowlarr_get "/appProfile" | jq -r 'first(.[].id) // 1' 2>/dev/null)
  app_profile_id=${app_profile_id:-1}

  # Wire up FlareSolverr tag so Cloudflare-protected indexers use it during the connectivity test
  local tags proxy_id proxy_obj proxies
  tags=$(prowlarr_get "/tag" 2>/dev/null) || tags="[]"
  flare_tag_id=$(echo "$tags" | jq -r 'first(.[] | select(.label == "flaresolverr") | .id) // empty' 2>/dev/null)
  if [[ -z "$flare_tag_id" ]]; then
    flare_tag_id=$(prowlarr_post "/tag" '{"label":"flaresolverr"}' | jq -r '.id // empty' 2>/dev/null)
  fi
  if [[ -n "$flare_tag_id" ]]; then
    proxies=$(prowlarr_get "/indexerproxy" 2>/dev/null) || proxies="[]"
    proxy_id=$(echo "$proxies" | jq -r 'first(.[] | select(.implementation == "FlareSolverr") | .id) // empty' 2>/dev/null)
    if [[ -n "$proxy_id" ]]; then
      proxy_obj=$(echo "$proxies" | jq --argjson id "$proxy_id" 'first(.[] | select(.id == $id))' 2>/dev/null)
      if ! echo "$proxy_obj" | jq -e --argjson t "$flare_tag_id" 'any(.tags[]?; . == $t)' &>/dev/null; then
        if curl -sf -X PUT -H "X-Api-Key: ${PROWLARR_KEY}" -H "Content-Type: application/json" \
             -d "$(echo "$proxy_obj" | jq --argjson t "$flare_tag_id" '.tags += [$t]')" \
             "${PROWLARR_URL}/api/v1/indexerproxy/${proxy_id}" >/dev/null; then
          log_ok "Prowlarr: FlareSolverr proxy tagged (id: ${flare_tag_id})"
        else
          log_warn "Prowlarr: failed to tag FlareSolverr proxy"
        fi
      else
        log_skip "Prowlarr: FlareSolverr proxy already tagged"
      fi
    fi
  fi

  # Public indexers: "Display Name|definition-file|needs-flaresolverr"
  local -a INDEXERS=(
    "1337x|1337x|1"
    "The Pirate Bay|thepiratebay|0"
    "EZTV|eztv|1"
    "YTS|yts|0"
    "Nyaa.si|nyaasi|0"
    "LimeTorrents|limetorrents|0"
    "KickassTorrents|kickasstorrents-ws|0"
    "MagnetDL|magnetdownload|0"
  )

  local display_name def_file needs_flare rest schema payload
  for entry in "${INDEXERS[@]}"; do
    display_name="${entry%%|*}"
    rest="${entry#*|}"
    def_file="${rest%%|*}"
    needs_flare="${rest##*|}"

    # Use jq for the exists check (handles names with spaces correctly)
    if echo "$existing" | jq -e --arg n "$display_name" 'any(.[]; .name == $n)' &>/dev/null; then
      log_skip "Prowlarr: ${display_name} already added"
      continue
    fi

    schema=$(echo "$all_schemas" | jq --arg d "$def_file" \
      'first(.[] | select(any(.fields[]?; .name == "definitionFile" and .value == $d))) // null' \
      2>/dev/null)

    if [[ -z "$schema" || "$schema" == "null" ]]; then
      log_warn "Prowlarr: '${def_file}' not in schema library — skipping ${display_name}"
      continue
    fi

    if [[ "$needs_flare" == "1" && -n "$flare_tag_id" ]]; then
      payload=$(echo "$schema" | jq --arg n "$display_name" --argjson pid "$app_profile_id" --argjson tid "$flare_tag_id" \
        'del(.id) | .enable = true | .name = $n | .appProfileId = $pid | .tags = [$tid]')
    else
      payload=$(echo "$schema" | jq --arg n "$display_name" --argjson pid "$app_profile_id" \
        'del(.id) | .enable = true | .name = $n | .appProfileId = $pid')
    fi

    if prowlarr_post "/indexer" "$payload" >/dev/null; then
      log_ok "Prowlarr: indexer added — ${display_name}"
    else
      log_warn "Prowlarr: failed to add ${display_name}"
    fi
  done

  # Native (non-Cardigann) indexers: "Display Name|implementationName|needs-rutracker-creds"
  local -a NATIVE_INDEXERS=(
    "Knaben|Knaben|0"
    "Rutracker|Rutracker|1"
  )

  local impl_name needs_creds native_schema native_payload
  for entry in "${NATIVE_INDEXERS[@]}"; do
    display_name="${entry%%|*}"
    rest="${entry#*|}"
    impl_name="${rest%%|*}"
    needs_creds="${rest##*|}"

    if [[ "$needs_creds" == "1" && ( -z "$RUTRACKER_USER" || -z "$RUTRACKER_PASS" ) ]]; then
      log_skip "Prowlarr: ${display_name} — set RUTRACKER_USER / RUTRACKER_PASS in arr-setup.env to add"
      continue
    fi

    if echo "$existing" | jq -e --arg n "$display_name" 'any(.[]; .name == $n)' &>/dev/null; then
      log_skip "Prowlarr: ${display_name} already added"
      continue
    fi

    native_schema=$(echo "$all_schemas" | jq --arg impl "$impl_name" \
      'first(.[] | select(.implementationName == $impl)) // null' 2>/dev/null)

    if [[ -z "$native_schema" || "$native_schema" == "null" ]]; then
      log_warn "Prowlarr: '${impl_name}' not in schema library — skipping ${display_name}"
      continue
    fi

    if [[ "$needs_creds" == "1" ]]; then
      native_payload=$(echo "$native_schema" | jq \
        --arg n "$display_name" --argjson pid "$app_profile_id" \
        --arg user "$RUTRACKER_USER" --arg pass "$RUTRACKER_PASS" \
        'del(.id) | .enable = true | .name = $n | .appProfileId = $pid |
         .fields = (.fields | map(
           if .name == "username" then .value = $user
           elif .name == "password" then .value = $pass
           else . end
         ))')
    else
      native_payload=$(echo "$native_schema" | jq --arg n "$display_name" --argjson pid "$app_profile_id" \
        'del(.id) | .enable = true | .name = $n | .appProfileId = $pid')
    fi

    if prowlarr_post "/indexer" "$native_payload" >/dev/null; then
      log_ok "Prowlarr: indexer added — ${display_name}"
    else
      log_warn "Prowlarr: failed to add ${display_name}"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Bazarr: enable subtitle providers that work without credentials
# ─────────────────────────────────────────────────────────────────────────────
setup_bazarr_providers() {
  if ! command -v jq &>/dev/null; then
    log_warn "Bazarr: jq not found — skipping automatic subtitle provider setup"
    return
  fi

  local settings
  settings=$(curl -sf "${BAZARR_URL}/api/system/settings" -H "X-Api-Key: ${BAZARR_KEY}") || {
    log_warn "Bazarr: failed to fetch settings for provider setup"
    return
  }

  # Providers that work without credentials
  local -a no_auth=("yifysubtitles" "tvsubtitles" "supersubtitles")
  local -a to_add=()
  local current_providers
  current_providers=$(echo "$settings" | jq -r '.general.enabled_providers // [] | .[]' 2>/dev/null)

  for p in "${no_auth[@]}"; do
    if echo "$current_providers" | grep -qx "$p"; then
      log_skip "Bazarr: provider ${p} already enabled"
    else
      to_add+=("$p")
    fi
  done

  if [[ ${#to_add[@]} -eq 0 ]]; then
    return
  fi

  local new_providers_json merged_list payload
  new_providers_json=$(printf '%s\n' "${to_add[@]}" | jq -R . | jq -s .)
  merged_list=$(echo "$settings" | jq --argjson new "$new_providers_json" \
    '(.general.enabled_providers // []) + $new | unique | sort')
  payload=$(jq -n --argjson p "$merged_list" '{"general":{"enabled_providers":$p}}')

  if curl -sf -X POST "${BAZARR_URL}/api/system/settings" \
       -H "X-Api-Key: ${BAZARR_KEY}" -H "Content-Type: application/json" \
       -d "$payload" >/dev/null; then
    log_ok "Bazarr: subtitle providers enabled — ${to_add[*]}"
  else
    log_warn "Bazarr: failed to enable subtitle providers — add manually at localhost:6767"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# qBittorrent: verify web UI credentials
# ─────────────────────────────────────────────────────────────────────────────
verify_qbit_login() {
  [[ -z "${QB_PASSWORD}" ]] && return
  log_info "Verifying qBittorrent credentials..."
  local body exit_code
  body=$(curl -sf -X POST "http://${QBIT_HOST}:8080/api/v2/auth/login" \
    --data-urlencode "username=${QB_USERNAME}" \
    --data-urlencode "password=${QB_PASSWORD}" 2>/dev/null)
  exit_code=$?
  # v5+: HTTP 204 No Content on success (curl exits 0, empty body)
  # v4:  HTTP 200 "Ok." on success, "Fails." on bad password
  if [[ $exit_code -eq 0 && "$body" != "Fails." ]]; then
    log_ok "qBittorrent: login verified ✓"
  else
    log_warn "qBittorrent: login failed — QB_PASSWORD may be incorrect"
    log_warn "  Get temp password: docker logs qbittorrent 2>&1 | grep -i password"
    log_warn "  Then update: echo QB_PASSWORD=<new> > ${SCRIPT_DIR}/arr-setup.env"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BOLD}${GREEN}"
echo "  ▄▄▄  ██████  ██████      ███████ ███████ ████████ ██    ██ ██████  "
echo " ██  ██ ██   ██ ██   ██     ██      ██         ██    ██    ██ ██   ██ "
echo " ███████ ██████  ██████      ███████ █████      ██    ██    ██ ██████  "
echo " ██  ██ ██   ██ ██   ██          ██ ██         ██    ██    ██ ██      "
echo " ██  ██ ██   ██ ██   ██     ███████ ███████    ██     ██████  ██      "
echo -e "${NC}"

# Prompt for QB_PASSWORD if not set and no --skip-qbit flag
if [[ -z "${QB_PASSWORD}" && "${SKIP_QBIT:-}" != "1" ]]; then
  echo -e "${YELLOW}qBittorrent password${NC} (leave blank to skip download client setup):"
  read -rsp "  > " QB_PASSWORD
  echo
fi

# ── Read API keys from config files ──────────────────────────────────────────
log_section "Reading API keys"

SONARR_KEY=$(extract_xml_api_key "${CONFIG_DIR}/sonarr/config.xml") \
  || die "Cannot read Sonarr API key — has the stack been started? (docker compose up -d)"
RADARR_KEY=$(extract_xml_api_key "${CONFIG_DIR}/radarr/config.xml") \
  || die "Cannot read Radarr API key"
PROWLARR_KEY=$(extract_xml_api_key "${CONFIG_DIR}/prowlarr/config.xml") \
  || die "Cannot read Prowlarr API key"

LIDARR_KEY=$(extract_xml_api_key "${CONFIG_DIR}/lidarr/config.xml") \
  || { log_warn "Lidarr config not found — Lidarr setup will be skipped"; LIDARR_KEY=""; }
READARR_KEY=$(extract_xml_api_key "${CONFIG_DIR}/readarr/config.xml") \
  || { log_warn "Readarr config not found — Readarr setup will be skipped"; READARR_KEY=""; }
BAZARR_KEY=$(extract_bazarr_api_key) \
  || true  # non-fatal
if [[ -z "${BAZARR_KEY:-}" ]]; then
  log_warn "Bazarr API key not found — Bazarr setup will be skipped"
fi

log_ok "API keys loaded"

# ── Wait for HTTP APIs ────────────────────────────────────────────────────────
log_section "Waiting for services"

wait_for_arr_service "Sonarr"   "$SONARR_URL"   "$SONARR_KEY"  v3 || SONARR_KEY=""
wait_for_arr_service "Radarr"   "$RADARR_URL"   "$RADARR_KEY"  v3 || RADARR_KEY=""
[[ -n "${LIDARR_KEY}"  ]] && { wait_for_arr_service "Lidarr"  "$LIDARR_URL"  "$LIDARR_KEY"  v1 || LIDARR_KEY=""; }
[[ -n "${READARR_KEY}" ]] && { wait_for_arr_service "Readarr" "$READARR_URL" "$READARR_KEY" v1 || READARR_KEY=""; }
wait_for_prowlarr || PROWLARR_KEY=""
[[ -n "${BAZARR_KEY:-}" ]] && { wait_for_bazarr || BAZARR_KEY=""; }

# ── Sonarr ────────────────────────────────────────────────────────────────────
if [[ -n "${SONARR_KEY}" ]]; then
  log_section "Sonarr"
  configure_arr "Sonarr" "$SONARR_URL" "$SONARR_KEY" "$TV_PATH" "tvCategory" "tv-sonarr"
fi

# ── Radarr ────────────────────────────────────────────────────────────────────
if [[ -n "${RADARR_KEY}" ]]; then
  log_section "Radarr"
  configure_arr "Radarr" "$RADARR_URL" "$RADARR_KEY" "$MOVIES_PATH" "movieCategory" "movies-radarr"
fi

# ── Lidarr ────────────────────────────────────────────────────────────────────
if [[ -n "${LIDARR_KEY}" ]]; then
  log_section "Lidarr"
  configure_arr "Lidarr" "$LIDARR_URL" "$LIDARR_KEY" "$MUSIC_PATH" "musicCategory" "music-lidarr" v1 "Music"
fi

# ── Readarr ───────────────────────────────────────────────────────────────────
if [[ -n "${READARR_KEY}" ]]; then
  log_section "Readarr"
  configure_arr "Readarr" "$READARR_URL" "$READARR_KEY" "$BOOKS_PATH" "bookCategory" "books-readarr" v1 "Books"
fi

# ── Prowlarr ──────────────────────────────────────────────────────────────────
if [[ -n "${PROWLARR_KEY}" ]]; then
  log_section "Prowlarr"
  setup_flaresolverr
  add_prowlarr_downloadclient
  [[ -n "${SONARR_KEY}"  ]] && add_prowlarr_app "Sonarr"  "SonarrSettings"  "$SONARR_HOST"  8989 "$SONARR_KEY"  '[5000,5010,5020,5030,5040,5045,5050,5090]'
  [[ -n "${RADARR_KEY}"  ]] && add_prowlarr_app "Radarr"  "RadarrSettings"  "$RADARR_HOST"  7878 "$RADARR_KEY"  '[2000,2010,2020,2030,2040,2045,2050,2060,2070,2080,2090]'
  [[ -n "${LIDARR_KEY}"  ]] && add_prowlarr_app "Lidarr"  "LidarrSettings"  "$LIDARR_HOST"  8686 "$LIDARR_KEY"  '[3000,3010,3020,3030,3040,3050,3060]'
  [[ -n "${READARR_KEY}" ]] && add_prowlarr_app "Readarr" "ReadarrSettings" "$READARR_HOST" 8787 "$READARR_KEY" '[7000,7010,7020,7030,7040,7050]'
  setup_prowlarr_indexers
fi

# ── Bazarr ────────────────────────────────────────────────────────────────────
if [[ -n "${BAZARR_KEY:-}" && -n "${SONARR_KEY}" && -n "${RADARR_KEY}" ]]; then
  log_section "Bazarr"
  configure_bazarr
  setup_bazarr_providers
fi

# ── qBittorrent ───────────────────────────────────────────────────────────────
log_section "qBittorrent"
verify_qbit_login

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}Setup complete!${NC}\n"
echo -e "  Remaining manual steps:"
echo -e "  • ${CYAN}Overseerr${NC}               — connect to Sonarr/Radarr via its web UI (Plex login required)"
echo -e "  • ${CYAN}Bazarr${NC}  (localhost:6767) — add subtitle providers that need credentials:"
echo -e "      → OpenSubtitles.com (most popular)  — free account at opensubtitles.com"
echo -e "      → Addic7ed (great for TV)            — free account at addic7ed.com"
echo -e "  • ${CYAN}Prowlarr${NC} (localhost:9696) — for Cloudflare-protected indexers (e.g. The Pirate"
echo -e "      Bay), assign the FlareSolverr proxy tag in Settings → Indexers\n"
