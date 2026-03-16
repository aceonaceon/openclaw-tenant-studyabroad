#!/usr/bin/env bash
set -e

# Usage: ./backup.sh [tenant-id]
# Without argument: backs up all tenants
# With argument: backs up specific tenant

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TENANTS_DIR="$BASE_DIR/tenants"
BACKUP_DIR="$BASE_DIR/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

backup_tenant() {
  local tenant="$1"
  local tenant_dir="$TENANTS_DIR/$tenant"

  if [ ! -d "$tenant_dir/workspace" ]; then
    echo "[lobster] ✗ Tenant '$tenant' has no workspace to backup"
    return 1
  fi

  local backup_file="$BACKUP_DIR/${tenant}_${TIMESTAMP}.tar.gz"

  tar -czf "$backup_file" \
    -C "$tenant_dir" \
    workspace/ \
    config/openclaw.json5 \
    .env

  echo "[lobster] ✓ $tenant → $backup_file"
}

if [ -n "$1" ]; then
  # Backup specific tenant
  backup_tenant "$1"
else
  # Backup all tenants
  for tenant_dir in "$TENANTS_DIR"/*/; do
    [ -d "$tenant_dir" ] || continue
    tenant=$(basename "$tenant_dir")
    backup_tenant "$tenant" || true
  done
fi

echo "[lobster] Backup complete. Files in: $BACKUP_DIR"
