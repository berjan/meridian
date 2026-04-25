#!/usr/bin/env bash
# Print container state and the Meridian /health response.
set -euo pipefail
cd "$(dirname "$0")"
docker compose ps
echo
echo "Health:"
curl -fsS http://127.0.0.1:3456/health || echo "(unreachable)"
echo
