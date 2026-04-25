#!/usr/bin/env bash
# Shared helpers for the Meridian macOS tunnel scripts.
set -euo pipefail

MERIDIAN_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERIDIAN_CONFIG_FILE="$MERIDIAN_INSTALL_DIR/config.env"

if [ -f "$MERIDIAN_CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$MERIDIAN_CONFIG_FILE"
fi

: "${MERIDIAN_SSH_HOST:=3090-ai}"
: "${MERIDIAN_LOCAL_HOST:=127.0.0.1}"
: "${MERIDIAN_LOCAL_API_PORT:=3456}"
: "${MERIDIAN_REMOTE_HOST:=127.0.0.1}"
: "${MERIDIAN_REMOTE_PORT:=3456}"
: "${MERIDIAN_DASHBOARD_PROXY_PORT:=3457}"
: "${MERIDIAN_STOP_LOCAL_DOCKER:=1}"

MERIDIAN_TUNNEL_LABEL="it.bruens.meridian-tunnel"
MERIDIAN_DASHBOARD_PROXY_LABEL="it.bruens.meridian-dashboard-proxy"
MERIDIAN_MENUBAR_LABEL="it.bruens.meridian-tunnel-menubar"

launch_domain() {
  printf 'gui/%s' "$(id -u)"
}

plist_path() {
  printf '%s/Library/LaunchAgents/%s.plist' "$HOME" "$1"
}

ensure_launchagent_dir() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
}
