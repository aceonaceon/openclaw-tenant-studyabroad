#!/usr/bin/env bash
set -e

# Usage: ./update-all.sh
# Pulls latest image and restarts all tenant containers

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TENANTS_DIR="$BASE_DIR/tenants"

if [ ! -d "$TENANTS_DIR" ]; then
  echo "[lobster] No tenants directory found. Nothing to update."
  exit 0
fi

UPDATED=0
FAILED=0

for tenant_dir in "$TENANTS_DIR"/*/; do
  [ -d "$tenant_dir" ] || continue
  tenant=$(basename "$tenant_dir")

  echo "[lobster] Updating tenant: $tenant"

  cd "$tenant_dir"

  if docker compose pull 2>/dev/null && docker compose up -d 2>/dev/null; then
    echo "[lobster] ✓ $tenant updated successfully"
    UPDATED=$((UPDATED + 1))
  else
    echo "[lobster] ✗ $tenant update failed"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "[lobster] Update complete: $UPDATED succeeded, $FAILED failed"
