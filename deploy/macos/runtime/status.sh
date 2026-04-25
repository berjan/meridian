#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "Meridian tunnel LaunchAgent:"
if launchctl print "$(launch_domain)/$MERIDIAN_TUNNEL_LABEL" >/dev/null 2>&1; then
  echo "  loaded: yes"
else
  echo "  loaded: no"
fi

echo "Port $MERIDIAN_LOCAL_API_PORT listener:"
if command -v lsof >/dev/null 2>&1 && /usr/sbin/lsof -nP -iTCP:"$MERIDIAN_LOCAL_API_PORT" -sTCP:LISTEN 2>/dev/null; then
  true
else
  echo "  none"
fi

echo "Health:"
if curl -fsS --max-time 3 "http://${MERIDIAN_LOCAL_HOST}:${MERIDIAN_LOCAL_API_PORT}/health" >/tmp/meridian-tunnel-health.json 2>/tmp/meridian-tunnel-health.err; then
  python3 - <<'PY'
import json
p='/tmp/meridian-tunnel-health.json'
d=json.load(open(p))
print('  ok:', d.get('status'), 'version:', d.get('version'), 'mode:', d.get('mode'), 'loggedIn:', d.get('auth',{}).get('loggedIn'))
PY
else
  echo "  failed: $(cat /tmp/meridian-tunnel-health.err 2>/dev/null || true)"
fi
