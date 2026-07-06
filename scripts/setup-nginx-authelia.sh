#!/usr/bin/env bash
# Automated NGINX Proxy Manager + Authelia Setup
# Creates proxy hosts for all services with forward authentication.
# Idempotent: skips hosts that already exist.
# Usage: ./scripts/setup-nginx-authelia.sh [--nginx-url URL] [--nginx-user USER] [--nginx-pass PASS] [--domain DOMAIN]

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-nginx-authelia.sh [options]

Options:
  --nginx-url <url>    NGINX Proxy Manager base URL (default: http://localhost:81)
  --nginx-user <user>  NGINX Proxy Manager admin identity (default: admin@example.com)
  --nginx-pass <pass>  NGINX Proxy Manager admin secret (default: changeme)
  --domain <domain>    Base domain for proxy hosts (default: home.lab)
  -h, --help           Show this help
EOF
}

NGINX_URL="http://localhost:81"
NGINX_USER="admin@example.com"
NGINX_PASS="changeme"
DOMAIN="home.lab"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nginx-url) NGINX_URL="$2"; shift 2 ;;
    --nginx-url=*) NGINX_URL="${1#*=}"; shift ;;
    --nginx-user) NGINX_USER="$2"; shift 2 ;;
    --nginx-user=*) NGINX_USER="${1#*=}"; shift ;;
    --nginx-pass) NGINX_PASS="$2"; shift 2 ;;
    --nginx-pass=*) NGINX_PASS="${1#*=}"; shift ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --domain=*) DOMAIN="${1#*=}"; shift ;;
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

# Use $user/$groups/$name/$email — not $remote_user, which conflicts with nginx built-ins.
# proxy_pass targets authelia by container name so the subrequest stays on the Docker
# internal network and never loops back through nginx's own authelia.home.lab proxy host.
get_authelia_npm_advanced_config() {
  cat <<'EOF'
location = /authelia/api/verify {
    internal;
    proxy_pass http://authelia:9091/api/verify;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $remote_addr;
}

auth_request /authelia/api/verify;
auth_request_set $user $upstream_http_remote_user;
auth_request_set $groups $upstream_http_remote_groups;
auth_request_set $name $upstream_http_remote_name;
auth_request_set $email $upstream_http_remote_email;
error_page 401 =302 https://authelia.home.lab/?rd=$scheme://$http_host$request_uri;
EOF
}

# test_proxy_host_needs_repair <proxy_host_json> <use_auth:true|false>
test_proxy_host_needs_repair() {
  local proxy_host_json="$1" use_auth="$2"
  local config nginx_online nginx_err

  if [[ "$use_auth" == "true" ]]; then
    config="$(printf '%s' "$proxy_host_json" | jq -r '.advanced_config // ""')"
    if [[ "$config" =~ \$remote_user|\$remote_groups|\$remote_name|\$remote_email ]]; then
      return 0
    fi
    if [[ "$config" =~ proxy_pass[[:space:]]+https?://authelia\.home\.lab/api/verify ]]; then
      return 0
    fi
  fi

  nginx_online="$(printf '%s' "$proxy_host_json" | jq -r '.meta.nginx_online')"
  if [[ "$nginx_online" == "false" ]]; then
    return 0
  fi

  nginx_err="$(printf '%s' "$proxy_host_json" | jq -r '.meta.nginx_err // ""')"
  if [[ -n "$nginx_err" && "$nginx_err" != "null" ]]; then
    return 0
  fi

  return 1
}

# new_npm_proxy_host_body <name> <host> <port> <ws:true|false> <domain> <use_auth:true|false>
new_npm_proxy_host_body() {
  local name="$1" host="$2" port="$3" ws="$4" domain="$5" use_auth="$6"
  local advanced_config=""

  if [[ "$use_auth" == "true" ]]; then
    advanced_config="$(get_authelia_npm_advanced_config)"
  fi

  jq -n \
    --arg domain_name "${name}.${domain}" \
    --arg forward_host "$host" \
    --argjson forward_port "$port" \
    --argjson allow_websocket_upgrade "$ws" \
    --arg advanced_config "$advanced_config" \
    --argjson use_auth "$use_auth" \
    '{
      domain_names: [$domain_name],
      forward_scheme: "http",
      forward_host: $forward_host,
      forward_port: $forward_port,
      allow_websocket_upgrade: $allow_websocket_upgrade
    } + (if $use_auth then {advanced_config: $advanced_config} else {} end)'
}

# npm_api <method> <path> [json_body]
# Sets NPM_API_STATUS / NPM_API_BODY; returns 0 on 2xx status.
npm_api() {
  local method="$1" path="$2" data="${3:-}"
  local -a curl_args=(-sS -w '\n%{http_code}' -X "$method")

  if [[ -n "${NPM_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${NPM_TOKEN}")
  fi
  if [[ -n "$data" ]]; then
    curl_args+=(-H "Content-Type: application/json" -d "$data")
  fi
  curl_args+=("${NGINX_URL}${path}")

  local resp status body
  resp="$(curl "${curl_args[@]}" 2>/dev/null || printf '\n000')"
  status="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  NPM_API_STATUS="$status"
  NPM_API_BODY="$body"

  [[ "$status" -ge 200 && "$status" -lt 300 ]]
}

write_info "[================================================]"
write_info "[  NGINX Proxy Manager + Authelia Auto Setup   ]"
write_info "[================================================]"
write_info "Target Domain: $DOMAIN"
write_info "NGINX PM URL:  $NGINX_URL"
write_info ""

write_info "STEP 1: Authenticating to NGINX PM..."
login_body="$(jq -n --arg identity "$NGINX_USER" --arg secret "$NGINX_PASS" '{identity: $identity, secret: $secret}')"

if ! npm_api POST "/api/tokens" "$login_body"; then
  write_err "[-] Setup failed: could not authenticate (HTTP $NPM_API_STATUS): $NPM_API_BODY"
  exit 1
fi

NPM_TOKEN="$(printf '%s' "$NPM_API_BODY" | jq -r '.token')"
write_success "[+] Authenticated successfully"
write_info ""

write_info "STEP 2: Loading existing proxy hosts..."
if ! npm_api GET "/api/nginx/proxy-hosts"; then
  write_err "[-] Setup failed: could not load proxy hosts (HTTP $NPM_API_STATUS): $NPM_API_BODY"
  exit 1
fi
existing_hosts="$(get_npm_proxy_host_list "$NPM_API_BODY")"
existing_count="$(printf '%s' "$existing_hosts" | jq 'length')"

# Find duplicate domain -> [ids] groups so we can remove all but the first.
dupe_groups="$(printf '%s' "$existing_hosts" | jq -c '
  [ .[] as $h | (($h.domain_names // [])[] | ascii_downcase) as $d | {domain: $d, id: $h.id} ]
  | group_by(.domain)
  | map({domain: .[0].domain, ids: (map(.id) | unique)})
  | map(select(.ids | length > 1))
')"

dedup_count=0
while IFS= read -r group; do
  [[ -z "$group" ]] && continue
  domain_key="$(printf '%s' "$group" | jq -r '.domain')"
  mapfile -t ids < <(printf '%s' "$group" | jq -r '.ids[1:][]')
  for id in "${ids[@]}"; do
    if npm_api DELETE "/api/nginx/proxy-hosts/$id"; then
      dedup_count=$((dedup_count + 1))
      existing_hosts="$(printf '%s' "$existing_hosts" | jq -c --argjson id "$id" '[.[] | select(.id != $id)]')"
    else
      write_warn "Could not remove duplicate proxy host for '$domain_key' (id $id): HTTP $NPM_API_STATUS"
    fi
  done
done < <(printf '%s' "$dupe_groups" | jq -c '.[]')

# Map lowercase domain -> the single surviving proxy host JSON object.
existing_domains="$(printf '%s' "$existing_hosts" | jq -c '
  reduce .[] as $h ({}; reduce (($h.domain_names // [])[] | ascii_downcase) as $d (.; .[$d] = (.[$d] // $h)))
')"

write_info "[+] Found $existing_count existing proxy host(s)"
if [[ "$dedup_count" -gt 0 ]]; then
  write_warn "[+] Removed $dedup_count duplicate proxy host(s)"
fi
write_info ""

write_info "STEP 3: Creating proxy hosts..."
write_info "============================================"
write_info ""

success_count=0
repair_count=0
skip_count=0
fail_count=0

for entry in "${HOMELAB_SERVICES[@]}"; do
  IFS='|' read -r svc_name svc_host svc_port svc_ws svc_skip_auth _ <<< "$entry"

  domain_name="${svc_name}.${DOMAIN}"
  domain_key="$(printf '%s' "$domain_name" | tr '[:upper:]' '[:lower:]')"
  if [[ "$svc_skip_auth" == "true" ]]; then use_auth="false"; else use_auth="true"; fi

  printf '\033[36m>> %s\033[0m' "$svc_name"

  existing_host="$(printf '%s' "$existing_domains" | jq -c --arg k "$domain_key" '.[$k] // empty')"

  if [[ -n "$existing_host" ]]; then
    if ! test_proxy_host_needs_repair "$existing_host" "$use_auth"; then
      write_warn " [=] (already exists)"
      skip_count=$((skip_count + 1))
      continue
    fi

    body="$(new_npm_proxy_host_body "$svc_name" "$svc_host" "$svc_port" "$svc_ws" "$DOMAIN" "$use_auth")"
    existing_id="$(printf '%s' "$existing_host" | jq -r '.id')"

    if npm_api PUT "/api/nginx/proxy-hosts/$existing_id" "$body"; then
      if [[ "$use_auth" == "true" ]]; then
        write_success " [~] (repaired Authelia auth config)"
      else
        write_success " [~] (repaired)"
      fi
      repair_count=$((repair_count + 1))
    else
      write_err " [-] FAILED: HTTP $NPM_API_STATUS: $NPM_API_BODY"
      fail_count=$((fail_count + 1))
    fi
    continue
  fi

  body="$(new_npm_proxy_host_body "$svc_name" "$svc_host" "$svc_port" "$svc_ws" "$DOMAIN" "$use_auth")"

  if npm_api POST "/api/nginx/proxy-hosts" "$body"; then
    if [[ "$use_auth" == "true" ]]; then
      write_success " [+] (with Authelia auth)"
    else
      write_success " [+]"
    fi
    success_count=$((success_count + 1))
  else
    write_err " [-] FAILED: HTTP $NPM_API_STATUS: $NPM_API_BODY"
    fail_count=$((fail_count + 1))
  fi
done

write_info ""
write_info "============================================"
write_info "RESULTS:"
write_success "  [+] Created: $success_count"
if [[ "$repair_count" -gt 0 ]]; then
  write_success "  [~] Repaired: $repair_count"
fi
if [[ "$skip_count" -gt 0 ]]; then
  write_warn "  [=] Skipped: $skip_count"
fi
if [[ "$fail_count" -gt 0 ]]; then
  write_err "  [-] Failed:  $fail_count"
fi

write_info ""
write_success "[+] NPM setup complete!"
write_info ""
write_info "Access services at: http://<service>.$DOMAIN"
write_info "  http://sonarr.$DOMAIN"
write_info "  http://plex.$DOMAIN"
write_info "  http://authelia.$DOMAIN"
