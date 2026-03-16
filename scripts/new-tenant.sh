#!/usr/bin/env bash
set -e

# Usage: ./new-tenant.sh <tenant-id> <port> <domain> [api-key]
# Example: ./new-tenant.sh client-a 21001 a.yourlobster.com sk-ant-xxx

TENANT="$1"
PORT="$2"
DOMAIN="$3"
API_KEY="${4:-}"
IMAGE="${LOBSTER_IMAGE:-lobster-base:latest}"

if [ -z "$TENANT" ] || [ -z "$PORT" ] || [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <tenant-id> <port> <domain> [api-key]"
  echo "Example: $0 client-a 21001 a.yourlobster.com sk-ant-xxx"
  exit 1
fi

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TENANT_DIR="$BASE_DIR/tenants/$TENANT"

if [ -d "$TENANT_DIR" ]; then
  echo "[error] Tenant '$TENANT' already exists at $TENANT_DIR"
  exit 1
fi

echo "[lobster] Creating tenant: $TENANT"

# Create directory structure
mkdir -p "$TENANT_DIR/config" "$TENANT_DIR/workspace/memory"

# Generate .env
cat > "$TENANT_DIR/.env" <<EOF
TENANT_NAME=$TENANT
PORT=$PORT
DOMAIN=$DOMAIN
ANTHROPIC_API_KEY=${API_KEY}
EOF

# Generate openclaw.json5
cat > "$TENANT_DIR/config/openclaw.json5" <<EOF
{
  identity: {
    name: "Lobster Assistant",
    theme: "helpful specialist assistant"
  },

  agent: {
    workspace: "/home/node/.openclaw/workspace",
    model: {
      primary: "anthropic/claude-sonnet-4-5"
    }
  },

  gateway: {
    bind: "lan",
    mode: "local"
  },

  skills: {
    load: {
      extraDirs: ["/opt/lobster/shared-skills"],
      watch: true,
      watchDebounceMs: 250
    }
  }
}
EOF

# Copy initial user files from templates
cp "$BASE_DIR/platform/USER.example.md" "$TENANT_DIR/workspace/USER.md"
cp "$BASE_DIR/platform/AGENTS.custom.example.md" "$TENANT_DIR/workspace/AGENTS.custom.md"
touch "$TENANT_DIR/workspace/MEMORY.md"

# Generate docker-compose.yml
cat > "$TENANT_DIR/compose.yml" <<EOF
services:
  openclaw:
    image: ${IMAGE}
    container_name: lobster_${TENANT}
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./config:/home/node/.openclaw
      - ./workspace:/home/node/.openclaw/workspace
    ports:
      - "${PORT}:18789"
EOF

# Fix permissions for node user (uid 1000)
chown -R 1000:1000 "$TENANT_DIR/config" "$TENANT_DIR/workspace" 2>/dev/null || true

# Start the container
cd "$TENANT_DIR"
docker compose up -d

echo "[lobster] Tenant '$TENANT' is running on port $PORT"
echo "[lobster] Domain: $DOMAIN"
echo "[lobster] Workspace: $TENANT_DIR/workspace/"
echo ""
echo "Next steps:"
echo "  1. Edit $TENANT_DIR/workspace/USER.md with client info"
echo "  2. Edit $TENANT_DIR/workspace/AGENTS.custom.md for custom rules"
echo "  3. Add Caddy reverse proxy entry for $DOMAIN"
