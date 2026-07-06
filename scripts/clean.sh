#!/usr/bin/env bash
# Clean up config and data folders from all stacks while preserving .env files.
# Usage: ./scripts/clean.sh [--force]

set -euo pipefail

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

STACKS=(adblock-stack homeassistant-stack plex-stack infra-stack minecraft-stack)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

remove_except_env() {
  local path="$1"
  [[ -d "$path" ]] || return 0

  echo "Cleaning: $path"
  for item in "$path"/* "$path"/.*; do
    local name
    name="$(basename "$item")"
    [[ "$name" == "." || "$name" == ".." ]] && continue
    if [[ "$name" == ".env" || "$name" == ".env.local" ]]; then
      echo "  Preserving: $name"
      continue
    fi
    [[ -e "$item" ]] || continue
    rm -rf -- "$item"
    echo "  Removed: $name"
  done
}

if ! $FORCE; then
  read -r -p "This will delete config/ and data/ folders (except .env files) in all stacks. Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

echo "Starting cleanup of config and data folders..."

for stack in "${STACKS[@]}"; do
  remove_except_env "$REPO_ROOT/$stack/config"
  remove_except_env "$REPO_ROOT/$stack/data"
done

echo "Cleanup complete!"
