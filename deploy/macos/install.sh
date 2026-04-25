#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is for macOS only." >&2
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SOURCE_DIR/../.." && pwd)"
INSTALL_DIR_DEFAULT="$HOME/Library/Application Support/Meridian Tunnel"
APP_DIR_DEFAULT="$HOME/Applications/Meridian Tunnel Status.app"

MERIDIAN_SSH_HOST="${MERIDIAN_SSH_HOST:-3090-ai}"
MERIDIAN_LOCAL_HOST="${MERIDIAN_LOCAL_HOST:-127.0.0.1}"
MERIDIAN_LOCAL_API_PORT="${MERIDIAN_LOCAL_API_PORT:-3456}"
MERIDIAN_REMOTE_HOST="${MERIDIAN_REMOTE_HOST:-127.0.0.1}"
MERIDIAN_REMOTE_PORT="${MERIDIAN_REMOTE_PORT:-3456}"
MERIDIAN_DASHBOARD_PROXY_PORT="${MERIDIAN_DASHBOARD_PROXY_PORT:-3457}"
MERIDIAN_STOP_LOCAL_DOCKER="${MERIDIAN_STOP_LOCAL_DOCKER:-1}"
INSTALL_DIR="$INSTALL_DIR_DEFAULT"
APP_DIR="$APP_DIR_DEFAULT"
CONFIGURE_PI=1
INSTALL_MENUBAR=1
START_NOW=1

usage() {
  cat <<EOF
Usage: deploy/macos/install.sh [options]

Installs a macOS menu-bar app and LaunchAgents that expose a shared remote
Meridian instance locally:

  Pi/API clients:  http://127.0.0.1:3456
  Browser UI:      http://127.0.0.1:3457/telemetry

Options:
  --ssh-host HOST             SSH host alias for the Meridian server [$MERIDIAN_SSH_HOST]
  --remote-host HOST          Host on the remote side of SSH [$MERIDIAN_REMOTE_HOST]
  --remote-port PORT          Remote Meridian port [$MERIDIAN_REMOTE_PORT]
  --local-host HOST           Local bind host [$MERIDIAN_LOCAL_HOST]
  --local-api-port PORT       Local tunnel port for Pi/API clients [$MERIDIAN_LOCAL_API_PORT]
  --dashboard-port PORT       Local dashboard proxy port [$MERIDIAN_DASHBOARD_PROXY_PORT]
  --install-dir DIR           Runtime script install dir [$INSTALL_DIR]
  --app-dir DIR               Menu-bar app bundle path [$APP_DIR]
  --no-pi-config              Do not update ~/.pi/agent/models.json
  --no-menubar                Install scripts/LaunchAgents only, no menu-bar app
  --no-start                  Install files only, do not start LaunchAgents
  -h, --help                  Show this help

MERIDIAN_API_KEY is read from the environment or ~/.env.local. If absent, the
installer prompts for it and stores it in ~/.env.local with chmod 600.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ssh-host) MERIDIAN_SSH_HOST="$2"; shift 2 ;;
    --remote-host) MERIDIAN_REMOTE_HOST="$2"; shift 2 ;;
    --remote-port) MERIDIAN_REMOTE_PORT="$2"; shift 2 ;;
    --local-host) MERIDIAN_LOCAL_HOST="$2"; shift 2 ;;
    --local-api-port) MERIDIAN_LOCAL_API_PORT="$2"; shift 2 ;;
    --dashboard-port) MERIDIAN_DASHBOARD_PROXY_PORT="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --app-dir) APP_DIR="$2"; shift 2 ;;
    --no-pi-config) CONFIGURE_PI=0; shift ;;
    --no-menubar) INSTALL_MENUBAR=0; shift ;;
    --no-start) START_NOW=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

read_meridian_key_from_env_local() {
  python3 - <<'PY'
import os, re, sys
p=os.path.expanduser('~/.env.local')
try:
    text=open(p, encoding='utf-8').read()
except FileNotFoundError:
    sys.exit(1)
m=re.search(r'^(?:export\s+)?MERIDIAN_API_KEY=(.*)$', text, re.M)
if not m:
    sys.exit(1)
val=m.group(1).strip()
if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
    val=val[1:-1]
if not val:
    sys.exit(1)
print(val)
PY
}

write_key_to_env_local() {
  local key="$1"
  MERIDIAN_API_KEY_VALUE="$key" python3 - <<'PY'
import os, re, tempfile
key=os.environ['MERIDIAN_API_KEY_VALUE']
p=os.path.expanduser('~/.env.local')
content=open(p, encoding='utf-8').read() if os.path.exists(p) else ''
block=(
    '\n# --- Meridian (shared SSH-tunneled instance) ---\n'
    '# Pi/API clients use: http://127.0.0.1:3456\n'
    '# Browser dashboard uses the local key-injecting proxy:\n'
    '#   http://127.0.0.1:3457/telemetry\n'
    f'export MERIDIAN_API_KEY={key}\n'
)
pat=re.compile(r'^(?:export\s+)?MERIDIAN_API_KEY=.*$', re.M)
if pat.search(content):
    new=pat.sub(f'export MERIDIAN_API_KEY={key}', content)
else:
    new=content
    if new and not new.endswith('\n'):
        new+='\n'
    new+=block
os.makedirs(os.path.dirname(p), exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix='.env.local.', dir=os.path.dirname(p) or '.')
with os.fdopen(fd, 'w', encoding='utf-8') as f:
    f.write(new)
os.chmod(tmp, 0o600)
os.replace(tmp, p)
PY
}

MERIDIAN_API_KEY_VALUE="${MERIDIAN_API_KEY:-}"
if [ -z "$MERIDIAN_API_KEY_VALUE" ]; then
  MERIDIAN_API_KEY_VALUE="$(read_meridian_key_from_env_local 2>/dev/null || true)"
fi
if [ -z "$MERIDIAN_API_KEY_VALUE" ]; then
  printf 'Paste MERIDIAN_API_KEY for the shared Meridian server: ' >&2
  stty -echo
  IFS= read -r MERIDIAN_API_KEY_VALUE
  stty echo
  printf '\n' >&2
fi
if [ -z "$MERIDIAN_API_KEY_VALUE" ]; then
  echo "MERIDIAN_API_KEY is required." >&2
  exit 1
fi
write_key_to_env_local "$MERIDIAN_API_KEY_VALUE"

echo "Installing Meridian macOS runtime to: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
find "$SOURCE_DIR/runtime" -maxdepth 1 -type f -exec cp {} "$INSTALL_DIR/" \;
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR/dashboard-proxy.py"

shell_quote() {
  printf "'"
  printf "%s" "$1" | sed "s/'/'\\''/g"
  printf "'"
}

cat > "$INSTALL_DIR/config.env" <<EOF
# Generated by deploy/macos/install.sh. Safe to edit, then restart via the menu.
MERIDIAN_INSTALL_DIR=$(shell_quote "$INSTALL_DIR")
MERIDIAN_SSH_HOST=$(shell_quote "$MERIDIAN_SSH_HOST")
MERIDIAN_LOCAL_HOST=$(shell_quote "$MERIDIAN_LOCAL_HOST")
MERIDIAN_LOCAL_API_PORT=$(shell_quote "$MERIDIAN_LOCAL_API_PORT")
MERIDIAN_REMOTE_HOST=$(shell_quote "$MERIDIAN_REMOTE_HOST")
MERIDIAN_REMOTE_PORT=$(shell_quote "$MERIDIAN_REMOTE_PORT")
MERIDIAN_DASHBOARD_PROXY_PORT=$(shell_quote "$MERIDIAN_DASHBOARD_PROXY_PORT")
MERIDIAN_STOP_LOCAL_DOCKER=$(shell_quote "$MERIDIAN_STOP_LOCAL_DOCKER")
EOF
chmod 600 "$INSTALL_DIR/config.env"

if [ "$CONFIGURE_PI" = "1" ]; then
  echo "Configuring Pi model provider 'meridian' in ~/.pi/agent/models.json"
  export MERIDIAN_API_KEY_VALUE MERIDIAN_LOCAL_HOST MERIDIAN_LOCAL_API_PORT REPO_ROOT
  python3 - <<'PY'
import json, os, pathlib, tempfile
home=pathlib.Path.home()
out=home/'.pi'/'agent'/'models.json'
out.parent.mkdir(parents=True, exist_ok=True)
if out.exists():
    try:
        data=json.loads(out.read_text())
    except Exception:
        data={}
else:
    data={}
data.setdefault('providers', {})
example=pathlib.Path(os.environ['REPO_ROOT'])/'deploy'/'pi'/'models.json.example'
provider=json.loads(example.read_text())['providers']['meridian']
provider['baseUrl']=f"http://{os.environ['MERIDIAN_LOCAL_HOST']}:{os.environ['MERIDIAN_LOCAL_API_PORT']}"
provider['apiKey']=os.environ['MERIDIAN_API_KEY_VALUE']
provider.setdefault('headers', {})['x-meridian-agent']='pi'
data['providers']['meridian']=provider
fd,tmp=tempfile.mkstemp(prefix='models.json.', dir=str(out.parent))
with os.fdopen(fd, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.chmod(tmp, 0o600)
os.replace(tmp, out)
PY
fi

if [ "$INSTALL_MENUBAR" = "1" ]; then
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found; skipping menu-bar app build. Install Xcode command line tools and rerun." >&2
  else
    echo "Building menu-bar app: $APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
    cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MeridianTunnelStatus</string>
  <key>CFBundleIdentifier</key>
  <string>it.bruens.meridian-tunnel-status</string>
  <key>CFBundleName</key>
  <string>Meridian Tunnel Status</string>
  <key>CFBundleDisplayName</key>
  <string>Meridian Tunnel Status</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST
    swiftc -O -framework Cocoa "$SOURCE_DIR/MenuBarApp.swift" -o "$APP_DIR/Contents/MacOS/MeridianTunnelStatus"
    chmod +x "$APP_DIR/Contents/MacOS/MeridianTunnelStatus"

    MENUBAR_LABEL="it.bruens.meridian-tunnel-menubar"
    MENUBAR_PLIST="$HOME/Library/LaunchAgents/$MENUBAR_LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    launchctl bootout "gui/$(id -u)" "$MENUBAR_PLIST" >/dev/null 2>&1 || true
    pkill -f "MeridianTunnelStatus" >/dev/null 2>&1 || true
    cat > "$MENUBAR_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$MENUBAR_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_DIR/Contents/MacOS/MeridianTunnelStatus</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/meridian-tunnel-menubar.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/meridian-tunnel-menubar.err.log</string>
</dict>
</plist>
PLIST
    chmod 600 "$MENUBAR_PLIST"
  fi
fi

if [ "$START_NOW" = "1" ]; then
  echo "Starting SSH tunnel and dashboard proxy."
  "$INSTALL_DIR/start.sh"
  "$INSTALL_DIR/dashboard-proxy-start.sh"
  if [ "$INSTALL_MENUBAR" = "1" ] && [ -x "$APP_DIR/Contents/MacOS/MeridianTunnelStatus" ]; then
    MENUBAR_LABEL="it.bruens.meridian-tunnel-menubar"
    MENUBAR_PLIST="$HOME/Library/LaunchAgents/$MENUBAR_LABEL.plist"
    launchctl bootstrap "gui/$(id -u)" "$MENUBAR_PLIST" >/dev/null 2>&1 || true
    launchctl enable "gui/$(id -u)/$MENUBAR_LABEL" >/dev/null 2>&1 || true
    launchctl kickstart -k "gui/$(id -u)/$MENUBAR_LABEL" >/dev/null 2>&1 || true
  fi
fi

cat <<EOF

Done.

Pi/API endpoint:       http://$MERIDIAN_LOCAL_HOST:$MERIDIAN_LOCAL_API_PORT
Browser dashboard:    http://$MERIDIAN_LOCAL_HOST:$MERIDIAN_DASHBOARD_PROXY_PORT/telemetry
Menu-bar app:         $APP_DIR
Runtime scripts:      $INSTALL_DIR

Useful commands:
  "$INSTALL_DIR/status.sh"
  "$INSTALL_DIR/dashboard-proxy-status.sh"
  "$INSTALL_DIR/restart.sh"
  "$INSTALL_DIR/uninstall.sh"
EOF
