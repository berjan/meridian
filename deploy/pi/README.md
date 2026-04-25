# Meridian + Pi (Docker)

Run [Meridian](https://github.com/rynfar/meridian) in Docker against your local
[Pi coding agent](https://github.com/mariozechner/pi-coding-agent) so Pi uses
your Anthropic Claude Pro/Max subscription instead of an API key.

This stack:

- Builds the Meridian image from this repository (with the Dockerfile fix
  that installs the native Claude Code CLI).
- Binds Meridian to `127.0.0.1:3456` only — never exposed on the LAN.
- Imports your Anthropic OAuth credentials from `~/.pi/agent/auth.json` (or
  `~/.env.local` as a fallback) into the container's volume so the SDK
  subprocess can authenticate.
- Configures Pi to talk to Meridian via a custom provider in
  `~/.pi/agent/models.json`.

## Prerequisites

- Docker (with Compose v2)
- Python 3 on the host (used by the OAuth import script)
- [`pi`](https://github.com/mariozechner/pi-coding-agent) installed and logged in
  to Anthropic (`pi`, then `/login` → Anthropic Claude Pro/Max). This
  populates `~/.pi/agent/auth.json` with `access` + `refresh` tokens.

> Alternative: put `export ANTHROPIC_OAUTH_TOKEN=...` in `~/.env.local`. This
> works for the initial connection, but Meridian cannot auto-refresh the
> token, so it expires every ~8 hours.

## First-time setup

```bash
git clone git@github.com:berjan/meridian.git
cd meridian/deploy/pi

# 1. Build, start, import OAuth credentials, wait for /health.
./start.sh

# 2. Tell Pi about the Meridian provider.
mkdir -p ~/.pi/agent
cp models.json.example ~/.pi/agent/models.json   # or merge into your existing one
```

Verify Pi can list the Meridian models:

```bash
pi --list-models meridian
```

## Daily usage

```bash
# Pick a model
pi --model meridian/claude-sonnet-4-6
pi --model meridian/claude-opus-4-7
pi --model meridian/claude-haiku-4-5-20251001

# With thinking level
pi --model meridian/claude-opus-4-7:high
```

Or interactively from inside Pi: `/model` → pick a `meridian/*` entry.

## Operations

```bash
./status.sh   # container state + /health response
./stop.sh     # stop containers (volumes preserved)
./start.sh    # build (if Dockerfile/source changed) + start + re-import OAuth
```

Inspect runtime logs:

```bash
docker compose logs -f proxy
```

Telemetry dashboard: <http://127.0.0.1:3456/telemetry>

## How it works

- `docker-compose.yml` runs the `proxy` service from the Meridian image with
  `MERIDIAN_DEFAULT_AGENT=pi` and `MERIDIAN_PASSTHROUGH=1`. Pi keeps executing
  its own tools on the host; Meridian only forwards `tool_use` blocks.
- `import-pi-claude-oauth.sh` reads `~/.pi/agent/auth.json` (preferred) or
  `~/.env.local` and writes a Claude Code-formatted credential file into the
  `claude-auth` volume.
- The container restarts after import so the SDK subprocess re-reads the
  fresh credentials.
- Volumes:
  - `claude-auth` — OAuth credentials (`~/.claude/.credentials.json`)
  - `meridian-config` — telemetry SQLite DB, profile config
  - `meridian-cache` — cross-proxy session resume cache

## Adding more models

Append entries to the `meridian.models` array in `~/.pi/agent/models.json`.
Meridian forwards whatever model string you send; it does not hardcode a list,
so any Claude model your Max subscription has access to will work (including
Sonnet/Opus 4.7 and newer).

## Troubleshooting

**`Claude Code native binary not found at /app/bin/shims/claude`**
You're running an old image that used the upstream `claude` shim instead of the
real CLI. Rebuild with `./start.sh` (or `docker compose build --no-cache proxy`).

**`Claude auth verification did not report loggedIn=true`**
The container couldn't read your OAuth credentials. Check that
`~/.pi/agent/auth.json` exists and has an `anthropic` entry of `type: "oauth"`
with both `access` and `refresh`. Run `pi`, then `/logout` and `/login` to
reset.

**Pi shows `claude-cli` User-Agent and Meridian misroutes the request**
Pi mimics Claude Code's User-Agent, so detection isn't reliable. The compose
file already sets `MERIDIAN_DEFAULT_AGENT=pi` and the example
`models.json` adds an `x-meridian-agent: pi` header — keep both.

**Token refresh failed after a few hours**
You probably bootstrapped from `ANTHROPIC_OAUTH_TOKEN` in `~/.env.local`,
which has no refresh token. Log in via Pi (`/login` → Anthropic), then re-run
`./import-pi-claude-oauth.sh` to write the refresh-capable credentials.
