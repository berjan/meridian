#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_launchagent_dir
PLIST="$(plist_path "$MERIDIAN_DASHBOARD_PROXY_LABEL")"
launchctl bootout "$(launch_domain)" "$PLIST" >/dev/null 2>&1 || true
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$MERIDIAN_DASHBOARD_PROXY_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$MERIDIAN_INSTALL_DIR/dashboard-proxy.py</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/meridian-dashboard-proxy.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/meridian-dashboard-proxy.err.log</string>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
</dict>
</plist>
PLIST
chmod 600 "$PLIST"
launchctl bootstrap "$(launch_domain)" "$PLIST"
launchctl enable "$(launch_domain)/$MERIDIAN_DASHBOARD_PROXY_LABEL" >/dev/null 2>&1 || true
launchctl kickstart -k "$(launch_domain)/$MERIDIAN_DASHBOARD_PROXY_LABEL" >/dev/null 2>&1 || true
sleep 1
"$MERIDIAN_INSTALL_DIR/dashboard-proxy-status.sh"
