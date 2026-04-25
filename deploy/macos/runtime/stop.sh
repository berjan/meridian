#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
launchctl bootout "$(launch_domain)" "$(plist_path "$MERIDIAN_TUNNEL_LABEL")" >/dev/null 2>&1 || true
echo "Meridian tunnel stopped."
