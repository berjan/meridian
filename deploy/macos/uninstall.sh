#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="${MERIDIAN_INSTALL_DIR:-$HOME/Library/Application Support/Meridian Tunnel}"
APP_DIR="${MERIDIAN_APP_DIR:-$HOME/Applications/Meridian Tunnel Status.app}"

if [ -x "$INSTALL_DIR/uninstall.sh" ]; then
  "$INSTALL_DIR/uninstall.sh"
else
  for label in it.bruens.meridian-tunnel-menubar it.bruens.meridian-dashboard-proxy it.bruens.meridian-tunnel; do
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
  done
fi

if [ "${1:-}" = "--remove-files" ]; then
  rm -rf "$INSTALL_DIR" "$APP_DIR"
  echo "Removed runtime scripts and app bundle."
else
  echo "To also remove files, rerun: deploy/macos/uninstall.sh --remove-files"
fi
