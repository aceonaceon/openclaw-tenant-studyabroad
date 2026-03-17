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

# Check if caddy is available (needed for password hashing)
if ! command -v caddy &>/dev/null; then
  echo "[error] caddy not found. Install Caddy first (needed for password hashing)."
  exit 1
fi

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TENANT_DIR="$BASE_DIR/tenants/$TENANT"

if [ -d "$TENANT_DIR" ]; then
  echo "[error] Tenant '$TENANT' already exists at $TENANT_DIR"
  exit 1
fi

# Generate WebChat login password (Caddy basic_auth)
WEBCHAT_PASSWORD=$(openssl rand -base64 12)
WEBCHAT_HASH=$(caddy hash-password --plaintext "$WEBCHAT_PASSWORD")

echo "[lobster] Creating tenant: $TENANT"

# Create directory structure
mkdir -p "$TENANT_DIR/config" "$TENANT_DIR/workspace/memory"

# Generate .env (this stays on the host, NOT inside the container filesystem)
cat > "$TENANT_DIR/.env" <<EOF
TENANT_NAME=$TENANT
PORT=$PORT
DOMAIN=$DOMAIN
MINIMAX_API_KEY=${API_KEY}
WEBCHAT_USER=$TENANT
WEBCHAT_PASSWORD=$WEBCHAT_PASSWORD
WEBCHAT_HASH=$WEBCHAT_HASH
EOF

# Generate openclaw.json
# Note: uses a mix of literal ${...} for OpenClaw env var refs and shell $DOMAIN for tenant domain.
# We use a temp file approach to avoid heredoc quoting issues.
cat > "$TENANT_DIR/config/openclaw.json" <<JSONEOF
{
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "model": {
        "primary": "minimax/MiniMax-M2.5",
        "fallbacks": []
      }
    },
    "list": [
      {
        "id": "main",
        "default": true,
        "identity": {
          "name": "Lobster Assistant",
          "theme": "helpful specialist assistant"
        }
      }
    ]
  },
  "models": {
    "mode": "merge",
    "providers": {
      "minimax": {
        "apiKey": "\${MINIMAX_API_KEY}",
        "baseUrl": "https://api.minimax.io/anthropic",
        "api": "anthropic-messages",
        "models": [
          {
            "id": "MiniMax-M2.5",
            "name": "MiniMax M2.5",
            "reasoning": true,
            "input": ["text"],
            "cost": { "input": 0.3, "output": 1.2 },
            "contextWindow": 200000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "gateway": {
    "bind": "lan",
    "mode": "local",
    "trustedProxies": ["172.16.0.0/12", "10.0.0.0/8", "192.168.0.0/16"],
    "auth": {
      "mode": "trusted-proxy",
      "trustedProxy": {
        "userHeader": "x-forwarded-user",
        "requiredHeaders": ["x-forwarded-proto", "x-forwarded-host"],
        "allowUsers": []
      }
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": [
        "https://${DOMAIN}",
        "http://localhost:${PORT}",
        "http://127.0.0.1:${PORT}"
      ]
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
    volumes:
      - ./config:/home/node/.openclaw
      - ./workspace:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:${PORT}:18789"
EOF

# Generate per-tenant Caddyfile snippet
cat > "$TENANT_DIR/Caddyfile" <<CADDYEOF
${DOMAIN} {
  basic_auth {
    ${TENANT} ${WEBCHAT_HASH}
  }

  @blocked path /api/settings /api/settings/* /api/admin /api/admin/*
  respond @blocked "403 Forbidden" 403

  reverse_proxy 127.0.0.1:${PORT} {
    header_up X-Forwarded-User {http.auth.user.id}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-Host {host}
  }
}
CADDYEOF

# Auto-register in main Caddyfile (add import if not already present)
CADDY_MAIN="/etc/caddy/Caddyfile"
IMPORT_LINE="import $TENANT_DIR/Caddyfile"
if [ -f "$CADDY_MAIN" ]; then
  if ! grep -qF "$IMPORT_LINE" "$CADDY_MAIN"; then
    echo "$IMPORT_LINE" >> "$CADDY_MAIN"
    echo "[lobster] Added import to $CADDY_MAIN"
  else
    echo "[lobster] Import already exists in $CADDY_MAIN"
  fi
  sudo systemctl reload caddy
  echo "[lobster] Caddy reloaded."
else
  echo "[lobster] WARNING: $CADDY_MAIN not found. Add this line manually:"
  echo "  $IMPORT_LINE"
fi

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
echo "  WebChat:  https://$DOMAIN/webchat"
echo "  Username: $TENANT"
echo "  Password: $WEBCHAT_PASSWORD"
echo ""
echo "Next steps:"
echo "  1. Edit $TENANT_DIR/workspace/USER.md with client info"
echo "  2. Edit $TENANT_DIR/workspace/AGENTS.custom.md for custom rules"
