#!/usr/bin/env bash
# Authelia Configuration Setup Script
# Generates secrets and password hashes, updates .env and users_database.yml
#
# Usage: ./scripts/setup-authelia.sh [--skip-secrets] [--skip-users] [--domain home.lab]

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-authelia.sh [options]

Options:
  --skip-secrets       Do not (re)generate Authelia secrets in infra-stack/.env
  --skip-users         Do not prompt for / regenerate user password hashes
  --domain <domain>    Base domain used for the configuration template (default: home.lab)
  -h, --help           Show this help
EOF
}

SKIP_SECRETS=false
SKIP_USERS=false
DOMAIN="home.lab"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-secrets) SKIP_SECRETS=true; shift ;;
    --skip-users) SKIP_USERS=true; shift ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --domain=*) DOMAIN="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

write_success() { printf '\033[32m%s\033[0m\n' "$*"; }
write_info()    { printf '\033[36m%s\033[0m\n' "$*"; }
write_warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
write_err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTHELIA_PATH="$PROJECT_ROOT/infra-stack/helper-setup/authelia"
ENV_PATH="$PROJECT_ROOT/infra-stack/.env"
CONFIG_DIR="$PROJECT_ROOT/infra-stack/config/authelia"
USERS_DB_PATH="$CONFIG_DIR/users_database.yml"
CONFIG_PATH="$CONFIG_DIR/configuration.yml"
TEMPLATE_DIR="$PROJECT_ROOT/infra-stack/templates/authelia"

write_info "[====================================================]"
write_info "[    Authelia Configuration Setup                    ]"
write_info "[===================================================="
write_info "Domain: $DOMAIN"
write_info ""

mkdir -p "$CONFIG_DIR"

if [[ ! -f "$CONFIG_PATH" && -f "$TEMPLATE_DIR/configuration.yml.example" ]]; then
  sed "s/{{DOMAIN}}/$DOMAIN/g" "$TEMPLATE_DIR/configuration.yml.example" > "$CONFIG_PATH"
  write_success "[OK] Created configuration.yml from template"
fi

if [[ ! -f "$USERS_DB_PATH" && -f "$TEMPLATE_DIR/users_database.yml.example" ]]; then
  cp "$TEMPLATE_DIR/users_database.yml.example" "$USERS_DB_PATH"
  write_success "[OK] Created users_database.yml from template"
fi

NOTIFY_PATH="$CONFIG_DIR/notification.txt"
if [[ ! -f "$NOTIFY_PATH" ]]; then
  : > "$NOTIFY_PATH"
fi

write_info ""

# Step 1: Generate Secrets
if ! $SKIP_SECRETS; then
  write_info "STEP 1: Generating Secrets..."
  write_info ""

  gen_secret() {
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -base64 24
    else
      # Fallback: 24 random bytes, base64-encoded (matches generate-secrets.bat's
      # PowerShell RNGCryptoServiceProvider fallback path).
      head -c 24 /dev/urandom | base64
    fi
  }

  jwt_secret="$(gen_secret)"
  session_secret="$(gen_secret)"
  encryption_key="$(gen_secret)"

  write_info "Generated secrets:"
  write_info "  JWT_SECRET (for session tokens): $jwt_secret"
  write_info "  SESSION_SECRET (for session encryption): $session_secret"
  write_info "  STORAGE_ENCRYPTION_KEY (for database encryption): $encryption_key"
  write_info ""

  if [[ -z "$jwt_secret" || -z "$session_secret" || -z "$encryption_key" ]]; then
    write_err "Failed to generate secrets"
    exit 1
  fi

  # Update .env file
  write_info "Updating .env file..."

  touch "$ENV_PATH"

  update_env_var() {
    local key="$1" value="$2"
    local escaped_value
    escaped_value=$(printf '%s' "$value" | sed -e 's/[\/&]/\\&/g')
    if grep -q "^${key}=" "$ENV_PATH" 2>/dev/null; then
      sed -i "s#^${key}=.*#${key}=${escaped_value}#" "$ENV_PATH"
    else
      printf '\n%s=%s\n' "$key" "$value" >> "$ENV_PATH"
    fi
  }

  update_env_var "AUTHELIA_JWT_SECRET" "$jwt_secret"
  update_env_var "AUTHELIA_SESSION_SECRET" "$session_secret"
  update_env_var "AUTHELIA_STORAGE_ENCRYPTION_KEY" "$encryption_key"

  write_success "[OK] .env file updated with secrets"
  write_info ""
fi

# Step 2: Generate User Passwords
if ! $SKIP_USERS; then
  write_info "STEP 2: Generating User Passwords..."
  write_info ""

  # Define users to set up: "username|displayname|email"
  users=("admin|Administrator|jerrod.sunderland@gmail.com")

  users_yaml=""
  users_yaml+="###############################################################################\r\n"
  users_yaml+="#                           Users Database                                    #\r\n"
  users_yaml+="###############################################################################\r\n\r\n"
  users_yaml+="users:\r\n"

  for user_entry in "${users[@]}"; do
    IFS='|' read -r username displayname email <<< "$user_entry"

    write_info "Setting up user: $username"

    read -r -s -p "  Enter password for $username: " plain_pass
    echo

    write_info "  Generating password hash..."
    hash_output="$(docker run --rm authelia/authelia:latest authelia crypto hash generate --password "$plain_pass" 2>&1)" || true

    # Grab the whole line containing the hash (last match, like the original
    # PowerShell script), then trim whitespace and any "Digest: " prefix.
    hash="$(printf '%s\n' "$hash_output" | grep '\$argon2' | tail -n1 || true)"
    hash="$(printf '%s' "$hash" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    hash="${hash#Digest: }"

    if [[ -z "$hash" ]]; then
      write_err "Failed to generate hash for user $username"
      write_info "Raw output was:"
      write_info "$hash_output"
      exit 1
    fi

    users_yaml+="\r\n"
    users_yaml+="  ${username} :\r\n"
    users_yaml+="    displayname : \"${displayname}\"\r\n"
    users_yaml+="    password : \"${hash}\"\r\n"
    users_yaml+="    email : ${email}\r\n"
    users_yaml+="    groups:\r\n"
    users_yaml+="      - users\r\n"

    write_success "  [OK] Password hash generated"
    write_info ""
  done

  # Update users_database.yml
  write_info "Updating users_database.yml..."
  printf '%b' "$users_yaml" > "$USERS_DB_PATH"
  write_success "[OK] users_database.yml updated"
  write_info ""
fi

# Summary
write_info "[===================================================="
write_success "[    Setup Complete!                                  ]"
write_info "[===================================================="
write_info ""

if ! $SKIP_SECRETS; then
  write_success "[OK] Secrets generated and added to infra-stack/.env"
  write_info "  - AUTHELIA_JWT_SECRET"
  write_info "  - AUTHELIA_SESSION_SECRET"
  write_info "  - AUTHELIA_STORAGE_ENCRYPTION_KEY"
  write_info ""
fi

if ! $SKIP_USERS; then
  write_success "[OK] User passwords hashed and added to users_database.yml"
  write_info "  - admin"
  write_info "  - reg"
  write_info ""
fi

write_info "[NEXT] Next Steps:"
write_info "  1. Run full bootstrap: npm run setup"
write_info "  2. Or start stacks:    npm run start:all"
write_info "  3. Configure NPM/DNS:   npm run setup:nginx && npm run setup:dns"
write_info ""

write_success "Done!"
