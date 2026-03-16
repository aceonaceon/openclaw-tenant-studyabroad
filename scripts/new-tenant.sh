#!/usr/bin/env bash
set -e

# Usage: ./new-tenant.sh <tenant-id> <port> <domain> [minimax-api-key]
# Example: ./new-tenant.sh client-a 21001 a.yourlobster.com eyxxxxxxxx

TENANT="$1"
PORT="$2"
DOMAIN="$3"
API_KEY="${4:-}"
IMAGE="${LOBSTER_IMAGE:-lobster-base:latest}"

if [ -z "$TENANT" ] || [ -z "$PORT" ] || [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <tenant-id> <port> <domain> [minimax-api-key]"
  echo "Example: $0 client-a 21001 a.yourlobster.com eyxxxxxxxx"
  exit 1
fi

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TENANT_DIR="$BASE_DIR/tenants/$TENANT"

if [ -d "$TENANT_DIR" ]; then
  echo "[error] Tenant '$TENANT' already exists at $TENANT_DIR"
  exit 1
fi

# Generate gateway token for WebChat authentication
GW_TOKEN=$(openssl rand -hex 16)

echo "[lobster] Creating tenant: $TENANT"

# Create directory structure
mkdir -p "$TENANT_DIR/config" "$TENANT_DIR/workspace/memory"

# Generate .env (this stays on the host, NOT inside the container filesystem)
cat > "$TENANT_DIR/.env" <<EOF
TENANT_NAME=$TENANT
PORT=$PORT
DOMAIN=$DOMAIN
MINIMAX_API_KEY=${API_KEY}
OPENCLAW_GATEWAY_TOKEN=${GW_TOKEN}
EOF

# Generate openclaw.json (uses ${...} env var references, never plaintext keys)
# Schema follows OpenClaw 2026.3.x config format:
#   - identity → agents.list[].identity
#   - agent.* → agents.defaults
#   - gateway.token → gateway.auth.token
cat > "$TENANT_DIR/config/openclaw.json" <<'JSONEOF'
{
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "model": {
        "primary": "minimax/MiniMax-M2.5"
      }
    },
    "list": [
      {
        "identity": {
          "name": "Lobster Assistant",
          "theme": "helpful specialist assistant"
        }
      }
    ]
  },
  "models": {
    "providers": {
      "minimax": {
        "apiKey": "${MINIMAX_API_KEY}",
        "baseUrl": "https://api.minimax.io/anthropic",
        "apiFormat": "anthropic-messages",
        "models": {
          "MiniMax-M2.5": {
            "reasoning": true,
            "inputTypes": ["text"],
            "cost": { "input": 0.3, "output": 1.2 },
            "contextWindow": 200000,
            "maxTokens": 8192
          }
        }
      }
    }
  },
  "gateway": {
    "bind": "lan",
    "mode": "local",
    "auth": {
      "type": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    }
  },
  "skills": {
    "load": {
      "extraDirs": ["/opt/lobster/shared-skills"],
      "watch": true,
      "watchDebounceMs": 250
    }
  }
}
JSONEOF

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
    environment:
      - MINIMAX_API_KEY=\${MINIMAX_API_KEY}
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
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

echo ""
echo "[lobster] ✓ Tenant '$TENANT' is running on port $PORT"
echo "[lobster] Workspace: $TENANT_DIR/workspace/"
echo ""
echo "Access:"
echo "  WebChat:  http://localhost:$PORT/webchat"
echo "  Domain:   https://$DOMAIN/webchat (after Caddy setup)"
echo "  Token:    $GW_TOKEN"
echo ""
echo "Next steps:"
echo "  1. Edit $TENANT_DIR/workspace/USER.md with client info"
echo "  2. Edit $TENANT_DIR/workspace/AGENTS.custom.md for custom rules"
echo "  3. Add Caddy reverse proxy entry for $DOMAIN"
