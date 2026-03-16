#!/usr/bin/env bash
set -e

WS="/home/node/.openclaw/workspace"
BASE="/opt/lobster/base-workspace"

# Ensure workspace and memory directories exist
mkdir -p "$WS/memory"

# --- Fixed files: overwrite every boot (stay in sync with image) ---
cp "$BASE/SOUL.md" "$WS/SOUL.md"
cp "$BASE/TOOLS.md" "$WS/TOOLS.md"
cp "$BASE/AGENTS.base.md" "$WS/AGENTS.base.md"

# --- Personalized files: create only if missing ---
[ -f "$WS/AGENTS.custom.md" ] || cp "$BASE/AGENTS.custom.example.md" "$WS/AGENTS.custom.md"
[ -f "$WS/USER.md" ] || cp "$BASE/USER.example.md" "$WS/USER.md"
[ -f "$WS/MEMORY.md" ] || touch "$WS/MEMORY.md"

# --- Rebuild AGENTS.md = base + custom (every boot) ---
cat "$WS/AGENTS.base.md" "$WS/AGENTS.custom.md" > "$WS/AGENTS.md"

echo "[lobster] Workspace initialized. Fixed files synced, personal files preserved."

exec "$@"
