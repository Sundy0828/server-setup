#!/usr/bin/env bash
# Configure AdGuard Home DNS rewrites for homelab *.home.lab domains.
# Usage: ./scripts/setup-adguard-dns.sh [--adguard-url URL] [--domain DOMAIN] \
#          [--homelab-host-ip IP] [--adguard-user USER] [--adguard-pass PASS] [--skip-prompt]

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-adguard-dns.sh [options]

Options:
  --adguard-url <url>      AdGuard Home base URL (auto-detected if omitted)
  --domain <domain>        Base domain for DNS rewrites (default: home.lab)
  --homelab-host-ip <ip>   IP address the domains should resolve to
                           (default: from infra-stack/.env HOMELAB_HOST_IP, else 192.168.0.54)
  --adguard-user <user>    AdGuard Home admin username
  --adguard-pass <pass>    AdGuard Home admin password
  --skip-prompt            Do not prompt for credentials if not provided
  -h, --help               Show this help
EOF
}

ADGUARD_URL=""
DOMAIN="home.lab"
HOMELAB_HOST_IP=""
ADGUARD_USER=""
ADGUARD_PASS=""
SKIP_PROMPT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adguard-url) ADGUARD_URL="$2"; shift 2 ;;
    --adguard-url=*) ADGUARD_URL="${1#*=}"; shift ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --domain=*) DOMAIN="${1#*=}"; shift ;;
    --homelab-host-ip) HOMELAB_HOST_IP="$2"; shift 2 ;;
    --homelab-host-ip=*) HOMELAB_HOST_IP="${1#*=}"; shift ;;
    --adguard-user) ADGUARD_USER="$2"; shift 2 ;;
    --adguard-user=*) ADGUARD_USER="${1#*=}"; shift ;;
    --adguard-pass) ADGUARD_PASS="$2"; shift 2 ;;
    --adguard-pass=*) ADGUARD_PASS="${1#*=}"; shift ;;
    --skip-prompt) SKIP_PROMPT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./homelab-services.sh
source "$SCRIPT_DIR/homelab-services.sh"

write_success() { printf '\033[32m%s\033[0m\n' "$*"; }
write_info()    { printf '\033[36m%s\033[0m\n' "$*"; }
write_warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
write_err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# join_by <separator> [items...] — "${arr[*]}" with IFS set only honors a
# single separator character, so build comma-space-joined lists manually.
join_by() {
  local sep="$1"; shift
  local out="" item first=true
  for item in "$@"; do
    if $first; then out="$item"; first=false; else out="${out}${sep}${item}"; fi
  done
  printf '%s' "$out"
}

test_adguard_api_reachable() {
  local base_url="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$base_url/control/status" || echo "000")"
  [[ "$code" == "200" || "$code" == "401" ]]
}

resolve_adguard_url() {
  local preferred_url="${1:-}"
  local -a candidates=()

  if [[ -n "$preferred_url" ]]; then
    candidates+=("${preferred_url%/}")
  fi
  candidates+=(
    "http://127.0.0.1:8081"
    "http://localhost:8081"
    "http://127.0.0.1:3002"
    "http://localhost:3002"
  )

  local seen=" " url
  for url in "${candidates[@]}"; do
    [[ "$seen" == *" $url "* ]] && continue
    seen="$seen$url "
    if test_adguard_api_reachable "$url"; then
      printf '%s\n' "$url"
      return 0
    fi
  done

  write_err "Could not reach AdGuard Home API. Tried: $(join_by ", " "${candidates[@]}")"
  write_err ""
  write_err "After first-time setup, AdGuard moves its admin API from port 3000 to port 80 inside the container."
  write_err "- First-run wizard: http://localhost:3002"
  write_err "- Admin UI + API (after setup): http://localhost:8081"
  write_err ""
  write_err "Ensure adblock-stack is running: npm run start:adblock"
  write_err "If you changed port mappings, pass --adguard-url explicitly."
  return 1
}

# adguard_api <method> <path> [json_body]
# Uses $ADGUARD_CRED_USER/$ADGUARD_CRED_PASS for basic auth if set.
# Sets ADGUARD_API_STATUS / ADGUARD_API_BODY; returns 0 on 2xx status.
adguard_api() {
  local method="$1" path="$2" data="${3:-}"
  local -a curl_args=(-sS -w '\n%{http_code}' -X "$method")

  if [[ -n "${ADGUARD_CRED_USER:-}" ]]; then
    curl_args+=(-u "${ADGUARD_CRED_USER}:${ADGUARD_CRED_PASS}")
  fi
  if [[ -n "$data" ]]; then
    curl_args+=(-H "Content-Type: application/json" -d "$data")
  fi
  curl_args+=("${ADGUARD_URL}${path}")

  local resp status body
  resp="$(curl "${curl_args[@]}" 2>/dev/null || printf '\n000')"
  status="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  ADGUARD_API_STATUS="$status"
  ADGUARD_API_BODY="$body"

  [[ "$status" -ge 200 && "$status" -lt 300 ]]
}

get_adguard_credential() {
  if [[ -n "$ADGUARD_USER" && -n "$ADGUARD_PASS" ]]; then
    ADGUARD_CRED_USER="$ADGUARD_USER"
    ADGUARD_CRED_PASS="$ADGUARD_PASS"
    return 0
  fi

  if ! $SKIP_PROMPT; then
    write_info ""
    write_info "AdGuard Home uses its own admin login from first-time setup at $ADGUARD_URL."
    write_info "This is NOT your Authelia or NPM password."
    read -r -p "AdGuard Home admin username [admin]: " prompted_user
    ADGUARD_CRED_USER="${prompted_user:-admin}"
    read -r -s -p "AdGuard Home admin password: " ADGUARD_CRED_PASS
    echo
    return 0
  fi

  return 1
}

if ! ADGUARD_URL="$(resolve_adguard_url "$ADGUARD_URL")"; then
  exit 1
fi

ENV_PATH="$(cd "$SCRIPT_DIR/.." && pwd)/infra-stack/.env"
TARGET_IP="$(get_homelab_host_ip "$HOMELAB_HOST_IP" "$ENV_PATH")"

write_info "[================================================]"
write_info "[       AdGuard DNS Rewrites Setup              ]"
write_info "[================================================]"
write_info "AdGuard URL: $ADGUARD_URL"
write_info "Domain:      *.$DOMAIN"
write_info ""

write_info "Homelab host IP: $TARGET_IP"
write_info ""

mapfile -t DOMAINS < <(get_homelab_dns_domains "$DOMAIN")

ADGUARD_CRED_USER=""
ADGUARD_CRED_PASS=""

if adguard_api GET "/control/rewrite/list"; then
  write_info "AdGuard API reachable without authentication."
  existing="$(printf '%s' "$ADGUARD_API_BODY" | jq -c 'if type == "array" then . else [.] end')"
else
  if ! get_adguard_credential; then
    write_warn "Skipping DNS rewrites (no AdGuard credentials)."
    write_warn "Add rewrites manually in AdGuard: Filters -> DNS rewrites -> point *.$DOMAIN to $TARGET_IP"
    exit 0
  fi
  if ! adguard_api GET "/control/rewrite/list"; then
    write_err "Failed to reach AdGuard rewrite list (HTTP $ADGUARD_API_STATUS): $ADGUARD_API_BODY"
    exit 1
  fi
  existing="$(printf '%s' "$ADGUARD_API_BODY" | jq -c 'if type == "array" then . else [.] end')"
fi

added=0
updated=0
skipped=0
deduped=0

for host_domain in "${DOMAINS[@]}"; do
  printf '\033[36m>> %s\033[0m' "$host_domain"

  rules="$(printf '%s' "$existing" | jq -c --arg d "$host_domain" '[.[] | select(.domain == $d)]')"
  rule_count="$(printf '%s' "$rules" | jq 'length')"
  correct_rules="$(printf '%s' "$rules" | jq -c --arg ip "$TARGET_IP" '[.[] | select(.answer == $ip)]')"
  stale_rules="$(printf '%s' "$rules" | jq -c --arg ip "$TARGET_IP" '[.[] | select(.answer != $ip)]')"
  correct_count="$(printf '%s' "$correct_rules" | jq 'length')"
  stale_count="$(printf '%s' "$stale_rules" | jq 'length')"

  if [[ "$correct_count" -eq 1 && "$stale_count" -eq 0 ]]; then
    write_success " [=] (already correct)"
    skipped=$((skipped + 1))
    continue
  fi

  while IFS= read -r stale_answer; do
    [[ -z "$stale_answer" ]] && continue
    body="$(jq -n --arg domain "$host_domain" --arg answer "$stale_answer" '{domain: $domain, answer: $answer}')"
    if adguard_api POST "/control/rewrite/delete" "$body"; then
      if [[ "$rule_count" -gt 1 ]]; then deduped=$((deduped + 1)); fi
    else
      write_err " [-] FAILED to remove stale rewrite ($stale_answer): HTTP $ADGUARD_API_STATUS"
    fi
  done < <(printf '%s' "$stale_rules" | jq -r '.[].answer')

  if [[ "$correct_count" -gt 1 ]]; then
    while IFS= read -r dup_answer; do
      [[ -z "$dup_answer" ]] && continue
      body="$(jq -n --arg domain "$host_domain" --arg answer "$dup_answer" '{domain: $domain, answer: $answer}')"
      if adguard_api POST "/control/rewrite/delete" "$body"; then
        deduped=$((deduped + 1))
      else
        write_err " [-] FAILED to remove duplicate rewrite: HTTP $ADGUARD_API_STATUS"
      fi
    done < <(printf '%s' "$correct_rules" | jq -r '.[1:][].answer')
  fi

  if [[ "$correct_count" -ge 1 ]]; then
    write_success " [~] (updated)"
    updated=$((updated + 1))
    continue
  fi

  body="$(jq -n --arg domain "$host_domain" --arg answer "$TARGET_IP" '{domain: $domain, answer: $answer}')"
  if adguard_api POST "/control/rewrite/add" "$body"; then
    write_success " [+] (added)"
    added=$((added + 1))
  else
    write_err " [-] FAILED: HTTP $ADGUARD_API_STATUS: $ADGUARD_API_BODY"
  fi
done

write_info ""
write_info "============================================"
write_success "  Added:   $added"
write_success "  Updated: $updated"
write_success "  Skipped: $skipped"
if [[ "$deduped" -gt 0 ]]; then
  write_success "  Deduped: $deduped"
fi
write_info ""
write_info "Ensure this machine uses AdGuard for DNS (port 53)."
write_success "Done!"
