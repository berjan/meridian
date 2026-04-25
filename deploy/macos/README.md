# Meridian macOS Tunnel + Menu Bar App

This directory installs a Mac-friendly client for a shared Meridian server.
It is designed for a setup where Meridian runs on another machine (for example
`3090-ai`) and the Mac should use it as if it were local.

After install:

- Pi/API clients use `http://127.0.0.1:3456`
- Browser dashboard uses `http://127.0.0.1:3457/telemetry`
- A native menu-bar app shows tunnel health and can restart/stop the tunnel

The browser dashboard uses a **local-only key-injecting proxy** on port 3457 so
normal browser requests can access Meridian without weakening API-key auth on the
LAN server.

## Requirements

- macOS with `/usr/bin/ssh`
- `python3` from macOS command line tools
- Swift compiler (`swiftc`) for the menu-bar app build. If missing, install
  Xcode Command Line Tools:

  ```bash
  xcode-select --install
  ```

- SSH alias or hostname for the Meridian server, defaulting to `3090-ai`
- The shared `MERIDIAN_API_KEY`
- Optional: Pi already installed (`npm install -g @mariozechner/pi-coding-agent`)

## Quick install

From a clone of this Meridian fork:

```bash
cd deploy/macos
./install.sh
```

The installer reads `MERIDIAN_API_KEY` from the environment or `~/.env.local`.
If it is missing, it prompts for it and stores it in `~/.env.local` with mode
`0600`.

For the default ViaFerry topology this is enough:

```bash
cd deploy/macos
./install.sh --ssh-host 3090-ai
```

For another SSH hostname:

```bash
./install.sh --ssh-host my-meridian-server
```

If the remote Meridian listens somewhere other than `127.0.0.1:3456` on the
server side:

```bash
./install.sh \
  --ssh-host my-meridian-server \
  --remote-host 127.0.0.1 \
  --remote-port 3456
```

## What gets installed

Runtime scripts and generated config:

```text
~/Library/Application Support/Meridian Tunnel/
├── config.env
├── run.sh
├── start.sh
├── stop.sh
├── restart.sh
├── status.sh
├── dashboard-proxy.py
├── dashboard-proxy-start.sh
├── dashboard-proxy-stop.sh
├── dashboard-proxy-status.sh
└── uninstall.sh
```

Menu-bar app:

```text
~/Applications/Meridian Tunnel Status.app
```

LaunchAgents:

```text
~/Library/LaunchAgents/it.bruens.meridian-tunnel.plist
~/Library/LaunchAgents/it.bruens.meridian-dashboard-proxy.plist
~/Library/LaunchAgents/it.bruens.meridian-tunnel-menubar.plist
```

Logs:

```text
~/Library/Logs/meridian-tunnel.log
~/Library/Logs/meridian-tunnel.err.log
~/Library/Logs/meridian-dashboard-proxy.log
~/Library/Logs/meridian-dashboard-proxy.err.log
~/Library/Logs/meridian-tunnel-menubar.log
~/Library/Logs/meridian-tunnel-menubar.err.log
```

## Menu-bar actions

The menu-bar item shows one of:

| Status | Meaning |
|---|---|
| `🟢 Meridian` | Tunnel healthy and Meridian is logged in |
| `🟡 Meridian` | Tunnel/port reachable but health has an issue |
| `🔴 Meridian` | Tunnel down or local port conflict |
| `⏳ Meridian` | Checking/restarting/stopping |

Menu actions:

- Open Telemetry Dashboard
- Open Meridian Health JSON
- Start / Restart Tunnel
- Stop Tunnel
- Refresh Status
- Open Tunnel Logs
- Open Tunnel Folder
- Quit Status App

## Pi integration

By default the installer updates `~/.pi/agent/models.json` by adding/updating the
`meridian` provider from `deploy/pi/models.json.example`, pointing it at:

```text
http://127.0.0.1:3456
```

The shared `MERIDIAN_API_KEY` is written into that Pi provider config with file
mode `0600`.

Use explicit Meridian models, for example:

```bash
pi --model meridian/claude-opus-4-7
pi --model meridian/claude-sonnet-4-6:high
pi --model meridian/claude-haiku-4-5-20251001
```

Skip Pi config if desired:

```bash
./install.sh --no-pi-config
```

## Manual commands

```bash
"$HOME/Library/Application Support/Meridian Tunnel/status.sh"
"$HOME/Library/Application Support/Meridian Tunnel/dashboard-proxy-status.sh"
"$HOME/Library/Application Support/Meridian Tunnel/restart.sh"
"$HOME/Library/Application Support/Meridian Tunnel/stop.sh"
"$HOME/Library/Application Support/Meridian Tunnel/start.sh"
```

## Uninstall

Stop LaunchAgents and remove plists, keeping installed files:

```bash
cd deploy/macos
./uninstall.sh
```

Also remove runtime scripts and the app bundle:

```bash
cd deploy/macos
./uninstall.sh --remove-files
```

This does **not** remove `MERIDIAN_API_KEY` from `~/.env.local` and does not
remove Pi's `~/.pi/agent/models.json`.
