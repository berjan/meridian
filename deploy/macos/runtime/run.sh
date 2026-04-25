#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

exec /usr/bin/ssh \
  -N \
  -L "${MERIDIAN_LOCAL_HOST}:${MERIDIAN_LOCAL_API_PORT}:${MERIDIAN_REMOTE_HOST}:${MERIDIAN_REMOTE_PORT}" \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o TCPKeepAlive=yes \
  -o BatchMode=yes \
  "$MERIDIAN_SSH_HOST"
