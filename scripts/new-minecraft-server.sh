#!/usr/bin/env bash
# Create a new Minecraft server from a template.
# Usage: ./scripts/new-minecraft-server.sh [--type <type>] [--port <port>] <name>
#   type: paper-survival (default) | vanilla-survival | vanilla-creative | curseforge | curseforge-manual | paper-hardcore

set -euo pipefail

VALID_TYPES=(paper-survival vanilla-survival vanilla-creative curseforge curseforge-manual paper-hardcore)

usage() {
  echo "Usage:"
  echo "  ./scripts/new-minecraft-server.sh [--type <type>] [--port <port>] <name>"
  echo ""
  echo "  type: ${VALID_TYPES[*]} (default: paper-survival)"
  echo ""
  echo "Or via npm shortcuts:"
  echo "  npm run new:minecraft:paper -- my-server"
  echo "  npm run new:minecraft:vanilla -- my-server"
  echo "  npm run new:minecraft:creative -- my-server"
  echo "  npm run new:minecraft:curseforge -- my-server"
  echo "  npm run new:minecraft:hardcore -- my-server"
}

TYPE="paper-survival"
PORT=0
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      TYPE="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  usage
  exit 1
fi

if ! printf '%s\n' "${VALID_TYPES[@]}" | grep -qx "$TYPE"; then
  echo "Error: invalid type '$TYPE'. Must be one of: ${VALID_TYPES[*]}" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/minecraft-stack/templates"
SERVERS_DIR="$REPO_ROOT/minecraft-stack/servers"
TEMPLATE_PATH="$TEMPLATES_DIR/$TYPE"
TARGET_PATH="$SERVERS_DIR/$NAME"

if [[ ! -d "$TEMPLATE_PATH" ]]; then
  echo "Error: template '$TYPE' not found at $TEMPLATE_PATH" >&2
  exit 1
fi

if [[ -e "$TARGET_PATH" ]]; then
  echo "Error: server '$NAME' already exists at minecraft-stack/servers/$NAME" >&2
  exit 1
fi

mkdir -p "$SERVERS_DIR"
cp -r "$TEMPLATE_PATH" "$TARGET_PATH"

ENV_EXAMPLE="$TARGET_PATH/.env.example"
ENV_FILE="$TARGET_PATH/.env"

if [[ -f "$ENV_EXAMPLE" ]]; then
  sed_args=(-e "s/^PLAYIT_CONTAINER_NAME=.*/PLAYIT_CONTAINER_NAME=playit-minecraft/")
  [[ "$PORT" -gt 0 ]] && sed_args+=(-e "s/^MC_PORT=.*/MC_PORT=$PORT/")
  sed "${sed_args[@]}" "$ENV_EXAMPLE" > "$ENV_FILE"
fi

echo ""
echo "Created server '$NAME' from template '$TYPE'"
echo "  Path: minecraft-stack/servers/$NAME"
echo ""
if [[ "$TYPE" == "curseforge" ]]; then
  echo "  Set CF_PAGE_URL and CF_API_KEY in .env, then:"
else
  echo "  Edit .env if needed, then:"
fi
echo "    cd minecraft-stack/servers/$NAME"
echo "    docker compose up -d"
echo ""
