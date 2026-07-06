#!/usr/bin/env bash
# Generate a *.home.lab wildcard certificate using mkcert and enable HTTPS on all NPM proxy hosts.
# mkcert installs a trusted local CA automatically — no manual cert import required.
# Idempotent: re-running always refreshes the cert files and re-uploads to NPM.
# Usage: ./scripts/setup-ssl-cert.sh [--nginx-url URL] [--nginx-user USER] [--nginx-pass PASS] [--domain DOMAIN] [--cert-dir DIR]
# Requires: mkcert (https://github.com/FiloSottile/mkcert) — install via your package
# manager (e.g. `apt install mkcert` on Debian 13) if the auto-install step below fails.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-ssl-cert.sh [options]

Options:
  --nginx-url <url>    NGINX Proxy Manager base URL (default: http://localhost:81)
  --nginx-user <user>  NGINX Proxy Manager admin identity (default: admin@example.com)
  --nginx-pass <pass>  NGINX Proxy Manager admin secret (default: changeme)
  --domain <domain>    Base domain for the wildcard cert (default: home.lab)
  --cert-dir <dir>     Output directory for cert/key files
                       (default: <repo>/infra-stack/data/nginx/certs)
  -h, --help           Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NGINX_URL="http://localhost:81"
NGINX_USER="admin@example.com"
NGINX_PASS="changeme"
DOMAIN="home.lab"
CERT_DIR="$PROJECT_ROOT/infra-stack/data/nginx/certs"

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
    --cert-dir) CERT_DIR="$2"; shift 2 ;;
    --cert-dir=*) CERT_DIR="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

write_success() { printf '\033[32m%s\033[0m\n' "$*"; }
write_info()    { printf '\033[36m%s\033[0m\n' "$*"; }
write_warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
write_err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# ---------------------------------------------------------------------------

assert_mkcert() {
  if ! command -v mkcert >/dev/null 2>&1; then
    write_info "  mkcert not found — attempting install..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y mkcert || true
    elif command -v brew >/dev/null 2>&1; then
      brew install mkcert || true
    fi
    if ! command -v mkcert >/dev/null 2>&1; then
      write_err "mkcert install failed or is unavailable — install it manually:"
      write_err "  https://github.com/FiloSottile/mkcert#installation"
      exit 1
    fi
  fi
}

# new_wildcard_cert <domain> <output_dir>
# Prints "<cert_file>|<key_file>" on success.
new_wildcard_cert() {
  local domain="$1" output_dir="$2"
  local cert_file="$output_dir/wildcard.crt"
  local key_file="$output_dir/wildcard.key"

  mkdir -p "$output_dir"

  assert_mkcert

  write_info "  Installing mkcert CA into system trust stores (idempotent)..." >&2
  mkcert -install

  write_info "  Generating wildcard cert for *.$domain and $domain..." >&2
  mkcert -cert-file "$cert_file" -key-file "$key_file" "*.$domain" "$domain"

  printf '%s|%s\n' "$cert_file" "$key_file"
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

# npm_api_upload_cert <cert_id> <cert_path> <key_path>
npm_api_upload_cert() {
  local cert_id="$1" cert_path="$2" key_path="$3"
  local resp status

  resp="$(curl -sS -w '\n%{http_code}' -X POST \
    -H "Authorization: Bearer ${NPM_TOKEN}" \
    -F "certificate=@${cert_path};type=text/plain" \
    -F "certificate_key=@${key_path};type=text/plain" \
    "${NGINX_URL}/api/nginx/certificates/${cert_id}/upload" 2>/dev/null || printf '\n000')"

  status="${resp##*$'\n'}"
  NPM_API_STATUS="$status"
  NPM_API_BODY="${resp%$'\n'*}"

  [[ "$status" -ge 200 && "$status" -lt 300 ]]
}

# ---------------------------------------------------------------------------

write_info "[================================================]"
write_info "[  NPM Wildcard TLS Setup - *.$DOMAIN          ]"
write_info "[================================================]"
write_info ""

# STEP 1 — generate cert via mkcert (always regenerates)
write_info "STEP 1: Generating wildcard certificate for *.$DOMAIN via mkcert..."
cert_paths="$(new_wildcard_cert "$DOMAIN" "$CERT_DIR")"
cert_file="${cert_paths%%|*}"
key_file="${cert_paths##*|}"
write_success "[+] Certificate : $cert_file"
write_success "[+] Private key  : $key_file"
write_info ""

# STEP 2 — authenticate to NPM
write_info "STEP 2: Authenticating to NGINX PM at $NGINX_URL..."
login_body="$(jq -n --arg identity "$NGINX_USER" --arg secret "$NGINX_PASS" '{identity: $identity, secret: $secret}')"
if ! npm_api POST "/api/tokens" "$login_body"; then
  write_err "[-] Setup failed: could not authenticate (HTTP $NPM_API_STATUS): $NPM_API_BODY"
  exit 1
fi
NPM_TOKEN="$(printf '%s' "$NPM_API_BODY" | jq -r '.token')"
write_success "[+] Authenticated"
write_info ""

# STEP 3 — upload cert to NPM (create record if new, always re-upload files)
write_info "STEP 3: Uploading certificate to NPM..."
nice_name="*.$DOMAIN Wildcard"

if ! npm_api GET "/api/nginx/certificates"; then
  write_err "[-] Setup failed: could not list certificates (HTTP $NPM_API_STATUS): $NPM_API_BODY"
  exit 1
fi
existing_certs="$(printf '%s' "$NPM_API_BODY" | jq -c 'if type == "array" then . else [.] end')"

cert_id="$(printf '%s' "$existing_certs" | jq -r --arg n "$nice_name" 'map(select(.nice_name == $n)) | .[0].id // empty')"

if [[ -n "$cert_id" ]]; then
  write_info "  Cert record exists (id $cert_id) — re-uploading fresh files..."
else
  create_body="$(jq -n --arg nice_name "$nice_name" '{provider: "other", nice_name: $nice_name}')"
  if ! npm_api POST "/api/nginx/certificates" "$create_body"; then
    write_err "[-] Setup failed: could not create certificate record (HTTP $NPM_API_STATUS): $NPM_API_BODY"
    exit 1
  fi
  cert_id="$(printf '%s' "$NPM_API_BODY" | jq -r '.id')"
  write_info "  Created new cert record (id $cert_id)..."
fi

if ! npm_api_upload_cert "$cert_id" "$cert_file" "$key_file"; then
  write_err "[-] Setup failed: could not upload certificate (HTTP $NPM_API_STATUS): $NPM_API_BODY"
  exit 1
fi
write_success "[+] Uploaded (id $cert_id)"
write_info ""

# STEP 4 — enable HTTPS on all proxy hosts
write_info "STEP 4: Enabling HTTPS on all proxy hosts..."
write_info "============================================"

if ! npm_api GET "/api/nginx/proxy-hosts"; then
  write_err "[-] Setup failed: could not list proxy hosts (HTTP $NPM_API_STATUS): $NPM_API_BODY"
  exit 1
fi
proxy_hosts="$(printf '%s' "$NPM_API_BODY" | jq -c 'if type == "array" then . else [.] end')"

updated=0
skipped=0
failed=0

proxy_host_count="$(printf '%s' "$proxy_hosts" | jq 'length')"
for (( i = 0; i < proxy_host_count; i++ )); do
  ph="$(printf '%s' "$proxy_hosts" | jq -c ".[$i]")"
  label="$(printf '%s' "$ph" | jq -r '(.domain_names // []) | join(", ")')"
  printf '\033[36m>> %s\033[0m' "$label"

  ph_cert_id="$(printf '%s' "$ph" | jq -r '.certificate_id')"
  if [[ "$ph_cert_id" == "$cert_id" ]]; then
    write_warn " [=] (already on this cert)"
    skipped=$((skipped + 1))
    continue
  fi

  update_body="$(printf '%s' "$ph" | jq \
    --argjson certificate_id "$cert_id" \
    '{
      domain_names: (.domain_names // []),
      forward_scheme: .forward_scheme,
      forward_host: .forward_host,
      forward_port: (.forward_port | tonumber),
      access_list_id: 0,
      certificate_id: $certificate_id,
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: (.advanced_config // ""),
      allow_websocket_upgrade: (.allow_websocket_upgrade // false),
      http2_support: true,
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false,
      locations: []
    }')"

  ph_id="$(printf '%s' "$ph" | jq -r '.id')"
  if npm_api PUT "/api/nginx/proxy-hosts/$ph_id" "$update_body"; then
    write_success " [+] (HTTPS enabled)"
    updated=$((updated + 1))
  else
    write_err " [-] FAILED: HTTP $NPM_API_STATUS: $NPM_API_BODY"
    failed=$((failed + 1))
  fi
done

write_info ""
write_info "============================================"
write_info "RESULTS:"
write_success "  [+] Updated : $updated"
if [[ "$skipped" -gt 0 ]]; then write_warn "  [=] Skipped : $skipped"; fi
if [[ "$failed" -gt 0 ]]; then write_err "  [-] Failed  : $failed"; fi
write_info ""

# STEP 5 — clean up stale self-signed certs from the local trust store.
# On Windows this removed leftover entries from Cert:\LocalMachine\Root. mkcert
# on Linux manages its own NSS/CA store instead, so there is no equivalent
# machine-wide store to prune here — just point at where the CA lives.
write_info "STEP 5: Local trust store cleanup"
if command -v mkcert >/dev/null 2>&1; then
  ca_root="$(mkcert -CAROOT)"
  write_info "  mkcert manages its own CA store; no stale-cert cleanup needed on Linux."
  write_info "  CA root: $ca_root"
else
  write_warn "  mkcert not found on PATH — skipping trust-store info."
fi
write_info ""

write_success "[+] TLS setup complete!"
write_info ""
write_info "The mkcert CA is already trusted on this machine."
write_warn "For other devices (phones, other PCs), copy and install the CA cert:"
if command -v mkcert >/dev/null 2>&1; then
  ca_root="$(mkcert -CAROOT)"
  write_warn "  $ca_root/rootCA.pem"
fi
