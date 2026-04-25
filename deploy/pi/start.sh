#!/usr/bin/env bash
# Build (if needed), start the Meridian Docker stack, import Pi's Anthropic
# OAuth credentials, and wait for the health endpoint to come up.
set -euo pipefail

cd "$(dirname "$0")"

docker compose up -d --build

# Import Pi's Anthropic OAuth credentials into the container's volume.
./import-pi-claude-oauth.sh

# Restart so the SDK subprocess re-reads the freshly imported auth state.
docker compose restart proxy >/dev/null

echo "Waiting for Meridian health endpoint..."
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:3456/health >/dev/null 2>&1; then
    echo "Meridian is running at http://127.0.0.1:3456"
    exit 0
  fi
  sleep 1
done

echo "Meridian did not become healthy within 30 seconds." >&2
docker compose logs --tail=80 proxy >&2
exit 1
