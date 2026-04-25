#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_launchagent_dir
PLIST="$(plist_path "$MERIDIAN_TUNNEL_LABEL")"

# If an old local Docker Meridian is occupying the API port, stop it so the
# SSH tunnel can transparently take over http://127.0.0.1:3456.
if [ "$MERIDIAN_STOP_LOCAL_DOCKER" = "1" ] && command -v lsof >/dev/null 2>&1; then
  if /usr/sbin/lsof -nP -iTCP:"$MERIDIAN_LOCAL_API_PORT" -sTCP:LISTEN 2>/dev/null | grep -q 'com.docke'; then
    for dir in "$HOME/workspace/meridian" "$HOME/workspace/meridian/repo/deploy/pi"; do
      if [ -f "$dir/docker-compose.yml" ] && command -v docker >/dev/null 2>&1; then
        (cd "$dir" && docker compose down >/dev/null 2>&1) || true
      fi
    done
  fi
fi

launchctl bootout "$(launch_domain)" "$PLIST" >/dev/null 2>&1 || true
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$MERIDIAN_TUNNEL_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$MERIDIAN_INSTALL_DIR/run.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/meridian-tunnel.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/meridian-tunnel.err.log</string>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
</dict>
</plist>
PLIST
chmod 600 "$PLIST"

launchctl bootstrap "$(launch_domain)" "$PLIST"
launchctl enable "$(launch_domain)/$MERIDIAN_TUNNEL_LABEL" >/dev/null 2>&1 || true
launchctl kickstart -k "$(launch_domain)/$MERIDIAN_TUNNEL_LABEL" >/dev/null 2>&1 || true
sleep 1
"$MERIDIAN_INSTALL_DIR/status.sh"
