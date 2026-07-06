#!/usr/bin/env bash
# Set AuthenticationMethod=External on all *arr apps so Authelia (reverse proxy) handles auth.
# The apps' built-in login page is suppressed; Authelia enforces access at the proxy level.
# Usage: ./scripts/set-arr-auth-external.sh
#        ./scripts/set-arr-auth-external.sh --plex-stack-path /path/to/plex-stack --dry-run

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: set-arr-auth-external.sh [options]

Options:
  --plex-stack-path <path>   Path to the plex-stack directory (default: <repo>/plex-stack)
  --dry-run                  Show what would change without writing files or restarting containers
  -h, --help                 Show this help
EOF
}

PLEX_STACK_PATH=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plex-stack-path) PLEX_STACK_PATH="$2"; shift 2 ;;
    --plex-stack-path=*) PLEX_STACK_PATH="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$PLEX_STACK_PATH" ]]; then
  PLEX_STACK_PATH="$(cd "$SCRIPT_DIR/.." && pwd)/plex-stack"
fi

if [[ ! -d "$PLEX_STACK_PATH" ]]; then
  write_err "plex-stack directory not found: $PLEX_STACK_PATH"
  exit 1
fi

# *arr apps that use config.xml with an AuthenticationMethod element.
# Bazarr and Overseerr use different config formats and are excluded.
ARR_APPS=(sonarr radarr lidarr prowlarr readarr)

get_auth_method() {
  python3 -c "
import sys
import xml.etree.ElementTree as ET
try:
    tree = ET.parse(sys.argv[1])
    el = tree.getroot().find('AuthenticationMethod')
    print(el.text if el is not None and el.text else '')
except Exception:
    print('')
" "$1"
}

set_auth_method_external() {
  python3 -c "
import sys
import xml.etree.ElementTree as ET
path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
el = root.find('AuthenticationMethod')
if el is None:
    el = ET.SubElement(root, 'AuthenticationMethod')
el.text = 'External'
tree.write(path, encoding='utf-8', xml_declaration=True)
" "$1"
}

changed=()
skipped=()
missing=()

for app in "${ARR_APPS[@]}"; do
  config_path="$PLEX_STACK_PATH/config/$app/config.xml"

  if [[ ! -f "$config_path" ]]; then
    write_warn "${app}: config.xml not found at $config_path - skipping"
    missing+=("$app")
    continue
  fi

  current="$(get_auth_method "$config_path")"

  if [[ "$current" == "External" ]]; then
    write_info "${app}: already External - no change"
    skipped+=("$app")
    continue
  fi

  write_info "${app}: ${current} -> External"

  if ! $DRY_RUN; then
    set_auth_method_external "$config_path"
  fi

  changed+=("$app")
done

if $DRY_RUN; then
  write_warn "Dry run mode - no files written, no containers restarted"
  exit 0
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  write_success "All apps already set to External. Nothing to restart."
  exit 0
fi

write_info ""
write_info "Restarting containers to apply changes: $(join_by ", " "${changed[@]}")"

for app in "${changed[@]}"; do
  write_info "  Restarting ${app}..."
  if ! docker restart "$app" >/dev/null; then
    write_warn "  docker restart ${app} failed - it may not be running"
  fi
done

write_info ""
write_success "Done."
write_success "  Changed : $(join_by ", " "${changed[@]}")"
if [[ ${#skipped[@]} -gt 0 ]]; then
  write_info "  Skipped : $(join_by ", " "${skipped[@]}") (already External)"
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  write_warn "  Missing : $(join_by ", " "${missing[@]}") (no config.xml found)"
fi
