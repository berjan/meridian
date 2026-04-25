#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

for label in "$MERIDIAN_MENUBAR_LABEL" "$MERIDIAN_DASHBOARD_PROXY_LABEL" "$MERIDIAN_TUNNEL_LABEL"; do
  launchctl bootout "$(launch_domain)" "$(plist_path "$label")" >/dev/null 2>&1 || true
  rm -f "$(plist_path "$label")"
done

echo "Meridian macOS LaunchAgents uninstalled."
echo "Installed scripts remain at: $MERIDIAN_INSTALL_DIR"
echo "Remove the app manually if desired: $HOME/Applications/Meridian Tunnel Status.app"
