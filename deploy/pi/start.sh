#!/usr/bin/env bash
# Build (if needed), start the Meridian Docker stack, import Pi's Anthropic
# OAuth credentials, and wait for the health endpoint to come up.
set -euo pipefail

cd "$(dirname "$0")"

# Load .env (if present) so the safety check below sees the same vars
# Compose will use. Compose itself also auto-loads ./.env.
if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

# Safety guard: never expose Meridian on the LAN without an API key.
bind="${MERIDIAN_BIND_HOST:-127.0.0.1}"
if [ "$bind" != "127.0.0.1" ] && [ "$bind" != "localhost" ] && [ -z "${MERIDIAN_API_KEY:-}" ]; then
  cat >&2 <<EOF
refusing to start: MERIDIAN_BIND_HOST=$bind exposes Meridian on the network
but MERIDIAN_API_KEY is empty. Anyone reaching the port could burn your
Claude Max subscription. Set MERIDIAN_API_KEY to a long random secret in
.env (or unset MERIDIAN_BIND_HOST to bind to loopback only).
EOF
  exit 1
fi

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
