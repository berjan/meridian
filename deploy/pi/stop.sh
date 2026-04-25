#!/usr/bin/env bash
# Stop the Meridian Docker stack. Volumes (credentials, telemetry, sessions)
# are preserved.
set -euo pipefail
cd "$(dirname "$0")"
docker compose down
