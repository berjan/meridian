#!/usr/bin/env bash
# Import the host's Anthropic OAuth credentials into the Meridian Docker
# volume so the Claude Code SDK subprocess inside the container can call
# Anthropic on behalf of the user.
#
# Source order (first that has both access + refresh tokens wins):
#   1. ~/.pi/agent/auth.json   (preferred — auto-refresh works)
#   2. ~/.env.local            (fallback — access token only, no auto-refresh)
#
# The container already has the SDK and the native Claude Code CLI installed,
# but no browser, so it cannot run `claude login` itself.
set -euo pipefail

cd "$(dirname "$0")"

if ! docker compose ps --status running proxy >/dev/null 2>&1; then
  echo "Meridian container is not running. Start it first with: ./start.sh" >&2
  exit 1
fi

python3 - <<'PY' | docker compose exec -T proxy sh -lc 'umask 077; mkdir -p /home/claude/.claude; cat > /home/claude/.claude/.credentials.json'
import json
import os
import re
import shlex
import sys

# Scopes Claude Code expects when reading the credential file.
SCOPES = [
    "user:profile",
    "user:inference",
    "user:sessions:claude_code",
    "user:mcp_servers",
    "user:file_upload",
]

def load_pi_auth():
    path = os.path.expanduser("~/.pi/agent/auth.json")
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    auth = data.get("anthropic")
    if not isinstance(auth, dict) or auth.get("type") != "oauth":
        return None
    return auth

def load_env_token():
    path = os.path.expanduser("~/.env.local")
    if not os.path.exists(path):
        return None
    for line in open(path, "r", encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"(?:export\s+)?ANTHROPIC_OAUTH_TOKEN=(.*)", line)
        if not m:
            continue
        raw = m.group(1).strip()
        try:
            parts = shlex.split(raw, comments=False, posix=True)
            return parts[0] if parts else ""
        except Exception:
            return raw.strip("'\"")
    return None

pi_auth = load_pi_auth()
if pi_auth and pi_auth.get("access") and pi_auth.get("refresh"):
    oauth = {
        "accessToken": pi_auth["access"],
        "refreshToken": pi_auth["refresh"],
        "expiresAt": int(pi_auth.get("expires") or 0),
        "scopes": SCOPES,
    }
else:
    # Last-resort fallback: setups that only have an access token in
    # ~/.env.local. Auto-refresh requires a refresh token, so prefer
    # ~/.pi/agent/auth.json whenever available.
    token = load_env_token()
    if not token:
        print(
            "No Anthropic OAuth credentials found in ~/.pi/agent/auth.json or ~/.env.local",
            file=sys.stderr,
        )
        sys.exit(1)
    oauth = {
        "accessToken": token,
        "refreshToken": "",
        "expiresAt": 0,
        "scopes": SCOPES,
    }

print(json.dumps({"claudeAiOauth": oauth}, separators=(",", ":")))
PY

echo "Imported Claude OAuth credentials into the Meridian Docker volume."

echo "Verifying Claude auth inside the container..."
last_auth=""
for _ in {1..10}; do
  last_auth="$(docker compose exec -T proxy claude auth status 2>&1 || true)"
  if printf '%s\n' "$last_auth" | grep -Eq '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
    echo "Claude auth OK."
    exit 0
  fi
  sleep 1
done

echo "Claude auth verification did not report loggedIn=true." >&2
echo "Container output:" >&2
printf '%s\n' "$last_auth" >&2
exit 1
