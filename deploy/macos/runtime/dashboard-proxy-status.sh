#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "Meridian dashboard proxy LaunchAgent:"
if launchctl print "$(launch_domain)/$MERIDIAN_DASHBOARD_PROXY_LABEL" >/dev/null 2>&1; then
  echo "  loaded: yes"
else
  echo "  loaded: no"
fi

echo "Port $MERIDIAN_DASHBOARD_PROXY_PORT listener:"
if command -v lsof >/dev/null 2>&1 && /usr/sbin/lsof -nP -iTCP:"$MERIDIAN_DASHBOARD_PROXY_PORT" -sTCP:LISTEN 2>/dev/null; then
  true
else
  echo "  none"
fi

echo "Proxy summary endpoint:"
if curl -fsS --max-time 3 "http://${MERIDIAN_LOCAL_HOST}:${MERIDIAN_DASHBOARD_PROXY_PORT}/telemetry/summary" >/tmp/meridian-dashboard-proxy-summary.json 2>/tmp/meridian-dashboard-proxy-summary.err; then
  python3 - <<'PY'
import json
p='/tmp/meridian-dashboard-proxy-summary.json'
d=json.load(open(p))
print('  ok: totalRequests=', d.get('totalRequests'), 'models=', ','.join(d.get('byModel', {}).keys()))
PY
else
  echo "  failed: $(cat /tmp/meridian-dashboard-proxy-summary.err 2>/dev/null || true)"
fi
