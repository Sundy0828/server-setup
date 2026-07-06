#!/usr/bin/env bash
# One-time homelab bootstrap: configs, stacks, NPM routes, AdGuard DNS, Authelia SSO.
# Interactive only for secrets/passwords that cannot be pre-generated safely.
# Usage: npm run setup

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-homelab.sh [options]

Options:
  --domain <domain>         Base domain (default: home.lab)
  --nginx-url <url>         NGINX Proxy Manager base URL (default: http://localhost:81)
  --adguard-url <url>       AdGuard Home base URL (default: http://localhost:3002)
  --authelia-url <url>      Authelia state endpoint used to wait for readiness
                            (default: http://authelia.home.lab/api/state)
  --skip-start              Skip starting Docker stacks
  --skip-nginx              Skip NGINX Proxy Manager route setup
  --skip-ssl                Skip wildcard TLS certificate setup
  --skip-dns                Skip AdGuard DNS rewrite setup
  --skip-stacks             Skip starting homeassistant-stack/plex-stack (adblock/infra still start)
  --skip-arr                Skip *arr app setup (download clients, root folders, Prowlarr, Bazarr)
  --skip-arr-auth           Skip setting *arr apps to External auth
  -h, --help                Show this help
EOF
}

DOMAIN="home.lab"
NGINX_URL="http://localhost:81"
ADGUARD_URL="http://localhost:3002"
AUTHELIA_URL="http://authelia.home.lab/api/state"
SKIP_START=false
SKIP_NGINX=false
SKIP_SSL=false
SKIP_DNS=false
SKIP_STACKS=false
SKIP_ARR=false
SKIP_ARR_AUTH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --domain=*) DOMAIN="${1#*=}"; shift ;;
    --nginx-url) NGINX_URL="$2"; shift 2 ;;
    --nginx-url=*) NGINX_URL="${1#*=}"; shift ;;
    --adguard-url) ADGUARD_URL="$2"; shift 2 ;;
    --adguard-url=*) ADGUARD_URL="${1#*=}"; shift ;;
    --authelia-url) AUTHELIA_URL="$2"; shift 2 ;;
    --authelia-url=*) AUTHELIA_URL="${1#*=}"; shift ;;
    --skip-start) SKIP_START=true; shift ;;
    --skip-nginx) SKIP_NGINX=true; shift ;;
    --skip-ssl) SKIP_SSL=true; shift ;;
    --skip-dns) SKIP_DNS=true; shift ;;
    --skip-stacks) SKIP_STACKS=true; shift ;;
    --skip-arr) SKIP_ARR=true; shift ;;
    --skip-arr-auth) SKIP_ARR_AUTH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=./homelab-services.sh
source "$SCRIPT_DIR/homelab-services.sh"

write_success() { printf '\033[32m%s\033[0m\n' "$*"; }
write_info()    { printf '\033[36m%s\033[0m\n' "$*"; }
write_warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
write_err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# wait_for_http <url> <label> [timeout_seconds] [insecure:true|false]
wait_for_http() {
  local url="$1" label="$2" timeout_seconds="${3:-120}" insecure="${4:-false}"
  local deadline=$(( $(date +%s) + timeout_seconds ))
  local code

  write_info "Waiting for $label ..."

  while (( $(date +%s) < deadline )); do
    if [[ "$insecure" == "true" ]]; then
      code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")"
    else
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")"
    fi

    if [[ "$code" != "502" && "$code" != "503" && "$code" != "504" && "$code" -ge 200 && "$code" -lt 500 ]]; then
      write_success "[+] $label is ready"
      return 0
    fi

    sleep 3
  done

  write_err "Timed out waiting for $label"
  return 1
}

copy_authelia_templates() {
  local domain="$1" config_dir="$2"
  local template_dir="$PROJECT_ROOT/infra-stack/templates/authelia"
  local config_file="$config_dir/configuration.yml"
  local users_file="$config_dir/users_database.yml"
  local notify_file="$config_dir/notification.txt"

  mkdir -p "$config_dir"

  if [[ ! -f "$config_file" ]]; then
    sed "s/{{DOMAIN}}/$domain/g" "$template_dir/configuration.yml.example" > "$config_file"
    write_success "[+] Created configuration.yml for domain '$domain'"
  else
    write_info "[=] configuration.yml already exists (skipping)"
  fi

  if [[ ! -f "$users_file" ]]; then
    cp "$template_dir/users_database.yml.example" "$users_file"
    write_success "[+] Created users_database.yml (passwords still needed)"
  else
    write_info "[=] users_database.yml already exists"
  fi

  if [[ ! -f "$notify_file" ]]; then
    : > "$notify_file"
  fi
}

# test_env_needs_secrets <env_path>
test_env_needs_secrets() {
  local env_path="$1"
  local key placeholder content

  [[ -f "$env_path" ]] || return 0

  content="$(cat "$env_path")"
  local placeholders=("your-jwt-secret-here" "your-session-secret-here" "your-encryption-key-here")

  for key in AUTHELIA_JWT_SECRET AUTHELIA_SESSION_SECRET AUTHELIA_STORAGE_ENCRYPTION_KEY; do
    if ! printf '%s' "$content" | grep -qE "${key}=.+"; then
      return 0
    fi
    for placeholder in "${placeholders[@]}"; do
      if printf '%s' "$content" | grep -qE "${key}=${placeholder}"; then
        return 0
      fi
    done
  done

  return 1
}

# test_users_need_setup <users_path>
test_users_need_setup() {
  local users_path="$1" content

  [[ -f "$users_path" ]] || return 0

  content="$(cat "$users_path")"

  if printf '%s' "$content" | grep -qE 'users:\s*\{\s*\}'; then
    return 0
  fi
  if ! printf '%s' "$content" | grep -qF '$argon2'; then
    return 0
  fi

  return 1
}

write_info ""
write_info "[====================================================]"
write_info "[           Homelab Bootstrap Setup                  ]"
write_info "[====================================================]"
write_info "Domain: $DOMAIN"
write_info ""

# Step 1: Docker network
write_info "STEP 1: Docker network"
if [[ -z "$(docker network ls --filter name=homelab --quiet 2>/dev/null)" ]]; then
  docker network create homelab >/dev/null
fi
write_success "[+] Network 'homelab' ready"
write_info ""

# Step 2: Environment file
write_info "STEP 2: Environment file"
ENV_PATH="$PROJECT_ROOT/infra-stack/.env"
ENV_EXAMPLE="$PROJECT_ROOT/infra-stack/.env.example"
if [[ ! -f "$ENV_PATH" && -f "$ENV_EXAMPLE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_PATH"
  write_success "[+] Created infra-stack/.env from .env.example"
else
  write_info "[=] infra-stack/.env already exists"
fi
write_info ""

# Step 3: Authelia config templates
write_info "STEP 3: Authelia configuration templates"
CONFIG_DIR="$PROJECT_ROOT/infra-stack/config/authelia"
copy_authelia_templates "$DOMAIN" "$CONFIG_DIR"
write_info ""

# Step 4: Secrets and user passwords (interactive when needed)
write_info "STEP 4: Authelia secrets and users"
USERS_PATH="$CONFIG_DIR/users_database.yml"

needs_secrets=false
needs_users=false
test_env_needs_secrets "$ENV_PATH" && needs_secrets=true
test_users_need_setup "$USERS_PATH" && needs_users=true

if $needs_secrets || $needs_users; then
  authelia_args=()
  $needs_secrets || authelia_args+=(--skip-secrets)
  $needs_users || authelia_args+=(--skip-users)

  if $needs_secrets; then
    write_info "Generating Authelia secrets -> infra-stack/.env"
  fi
  if $needs_users; then
    write_info "You will be prompted for SSO user passwords (admin, reg)."
  fi

  "$SCRIPT_DIR/setup-authelia.sh" "${authelia_args[@]}"
else
  write_success "[+] Authelia secrets and users already configured"
fi
write_info ""

# Step 5: Start stacks
if ! $SKIP_START; then
  write_info "STEP 5: Starting Docker stacks"
  write_info "  -> adblock-stack"
  (cd "$PROJECT_ROOT/adblock-stack" && docker compose up -d)

  write_warn ""
  write_warn "If this is the first AdGuard run, complete setup at $ADGUARD_URL"
  write_warn "Create an AdGuard admin account there (separate from Authelia/NPM)."
  write_warn "After setup, admin UI moves to http://localhost:8081 (DNS script auto-detects)."
  write_warn "You will be prompted for that same AdGuard login during DNS setup."
  write_warn ""

  if ! wait_for_http "$ADGUARD_URL" "AdGuard Home"; then
    write_warn "Continuing - finish AdGuard setup, then re-run: npm run setup:dns"
  fi

  write_info "  -> infra-stack"
  (cd "$PROJECT_ROOT/infra-stack" && docker compose up -d)

  wait_for_http "${NGINX_URL}/api/" "Nginx Proxy Manager API" || true
  wait_for_http "$AUTHELIA_URL" "Authelia" 120 true || true

  if ! $SKIP_STACKS; then
    for stack in homeassistant-stack plex-stack; do
      stack_path="$PROJECT_ROOT/$stack"
      if [[ -f "$stack_path/compose.yml" ]]; then
        write_info "  -> $stack"
        (cd "$stack_path" && docker compose up -d)
      fi
    done
  fi
  write_info ""
else
  write_info "STEP 5: Skipped stack startup (--skip-start)"
  write_info ""
fi

# Step 6: Arr app setup (download clients, root folders, Prowlarr, Bazarr)
if ! $SKIP_ARR; then
  write_info "STEP 6: Arr app setup (download clients, root folders, Prowlarr, Bazarr)"
  arr_setup_script="$PROJECT_ROOT/plex-stack/run-arr-setup.sh"
  if [[ -f "$arr_setup_script" ]]; then
    if ! bash "$arr_setup_script"; then
      write_warn "Arr setup exited with a non-zero code — continuing"
    fi
  else
    write_warn "[!] plex-stack/run-arr-setup.sh not found — skipping"
  fi
  write_info ""
else
  write_info "STEP 6: Skipped arr setup (--skip-arr)"
  write_info ""
fi

# Steps 7 + 8 both talk to NPM — resolve credentials once
nginx_user=""
nginx_pass_plain=""
if ! $SKIP_NGINX || ! $SKIP_SSL; then
  nginx_user="$(read_dotenv_value "$ENV_PATH" "NPM_ADMIN_EMAIL" "admin@example.com")"
  nginx_pass_plain="$(read_dotenv_value "$ENV_PATH" "NPM_ADMIN_PASSWORD" "changeme")"
  write_info "NPM login: $nginx_user (password from infra-stack/.env)"
  read -r -p "NPM admin password [Enter = value from .env]: " custom_pass
  if [[ -n "$custom_pass" ]]; then
    nginx_pass_plain="$custom_pass"
  fi
  write_info ""
fi

# Step 7: NPM proxy hosts + Authelia forward auth
if ! $SKIP_NGINX; then
  write_info "STEP 7: Nginx Proxy Manager routes + SSO"

  "$SCRIPT_DIR/setup-nginx-authelia.sh" \
    --nginx-url "$NGINX_URL" \
    --nginx-user "$nginx_user" \
    --nginx-pass "$nginx_pass_plain" \
    --domain "$DOMAIN"

  write_info ""
else
  write_info "STEP 7: Skipped NPM setup (--skip-nginx)"
  write_info ""
fi

# Step 8: Wildcard TLS certificate
if ! $SKIP_SSL; then
  write_info "STEP 8: Wildcard TLS certificate (*.$DOMAIN)"

  "$SCRIPT_DIR/setup-ssl-cert.sh" \
    --nginx-url "$NGINX_URL" \
    --nginx-user "$nginx_user" \
    --nginx-pass "$nginx_pass_plain" \
    --domain "$DOMAIN"

  write_info ""
else
  write_info "STEP 8: Skipped SSL setup (--skip-ssl)"
  write_info ""
fi

# Step 9: AdGuard DNS rewrites
if ! $SKIP_DNS; then
  write_info "STEP 9: AdGuard DNS rewrites"
  homelab_host_ip="$(get_homelab_host_ip "" "$ENV_PATH")"
  "$SCRIPT_DIR/setup-adguard-dns.sh" --adguard-url "$ADGUARD_URL" --domain "$DOMAIN" --homelab-host-ip "$homelab_host_ip" || true
  write_info ""
else
  write_info "STEP 9: Skipped DNS setup (--skip-dns)"
  write_info ""
fi

# Step 10: Restart Authelia to pick up config
write_info "STEP 10: Restarting Authelia"
# Docker writes progress to stderr; ignore that and rely on exit code.
if ! (cd "$PROJECT_ROOT/infra-stack" && docker compose restart authelia >/dev/null 2>&1); then
  exit 1
fi
write_success "[+] Authelia restarted"
write_info ""

# Step 11: Set *arr apps to External auth so Authelia handles login
if ! $SKIP_ARR_AUTH; then
  write_info "STEP 11: Set *arr app authentication to External"
  "$SCRIPT_DIR/set-arr-auth-external.sh" --plex-stack-path "$PROJECT_ROOT/plex-stack" || true
  write_info ""
else
  write_info "STEP 11: Skipped *arr auth setup (--skip-arr-auth)"
  write_info ""
fi

write_info "[====================================================]"
write_success "[           Setup complete!                          ]"
write_info "[====================================================]"
write_info ""
write_info "Try these URLs (after DNS propagates):"
write_info "  https://authelia.$DOMAIN      - SSO login portal"
write_info "  https://sonarr.$DOMAIN        - protected by Authelia"
write_info "  https://plex.$DOMAIN          - protected by Authelia"
write_info "  https://homepage.$DOMAIN      - dashboard"
write_info ""
write_info "Before DNS is ready, Authelia is also at:"
write_info "  https://127.0.0.1:9091        - direct (accept self-signed cert)"
write_info "  https://authelia.$DOMAIN:9091 - with hosts entry for $DOMAIN"
write_info ""
write_info "Admin UIs:"
write_info "  NPM:     $NGINX_URL  (change default password!)"
write_info "  AdGuard: $ADGUARD_URL"
write_info ""
write_info "Re-run individual steps:"
write_info "  npm run setup:nginx"
write_info "  npm run setup:ssl"
write_info "  npm run setup:dns"
write_info "  npm run setup:authelia"
write_info ""
