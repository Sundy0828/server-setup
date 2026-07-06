#!/usr/bin/env bash
# run-arr-setup.sh
# Linux launcher for arr-setup.sh — runs it inside a throwaway Alpine container
# attached to the homelab Docker network, so it can reach the *arr apps by
# their container names.
# Run this from the plex-stack directory after `docker compose up -d`.
# Usage: ./run-arr-setup.sh [--qb-password PASSWORD]
#        QB_PASSWORD=... ./run-arr-setup.sh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-arr-setup.sh [options]

Options:
  --qb-password <password>   qBittorrent web UI password (or set QB_PASSWORD env var)
  -h, --help                 Show this help
EOF
}

QB_PASSWORD="${QB_PASSWORD:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qb-password) QB_PASSWORD="$2"; shift 2 ;;
    --qb-password=*) QB_PASSWORD="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prompt for qBittorrent password if not provided
if [[ -z "$QB_PASSWORD" ]]; then
  read -r -s -p "qBittorrent password (leave blank to skip download client setup): " QB_PASSWORD
  echo
fi

# Verify Docker is running
if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker and try again." >&2
  exit 1
fi

printf '\033[36m%s\033[0m\n' "Starting arr-setup via Docker..."

docker run --rm \
  --network homelab \
  -v "${SCRIPT_DIR}:/setup" \
  -e SONARR_URL=http://sonarr:8989 \
  -e RADARR_URL=http://radarr:7878 \
  -e LIDARR_URL=http://lidarr:8686 \
  -e READARR_URL=http://readarr:8787 \
  -e PROWLARR_URL=http://prowlarr:9696 \
  -e BAZARR_URL=http://bazarr:6767 \
  -e QB_PASSWORD="$QB_PASSWORD" \
  alpine sh -c "apk add --no-cache bash curl jq python3 > /dev/null 2>&1 && bash /setup/arr-setup.sh"
