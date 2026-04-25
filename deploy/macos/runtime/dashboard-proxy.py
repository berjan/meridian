#!/usr/bin/env python3
"""Loopback-only Meridian dashboard proxy.

Reads MERIDIAN_API_KEY from ~/.env.local or the environment, then forwards
browser requests to the local Meridian tunnel while injecting x-api-key.
"""
from __future__ import annotations

import http.server
import os
import pathlib
import re
import socketserver
import sys
import urllib.error
import urllib.request


def read_config() -> dict[str, str]:
    p = pathlib.Path(__file__).resolve().parent / "config.env"
    out: dict[str, str] = {}
    if not p.exists():
        return out
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


CONFIG = read_config()
LISTEN_HOST = CONFIG.get("MERIDIAN_LOCAL_HOST", "127.0.0.1")
LISTEN_PORT = int(CONFIG.get("MERIDIAN_DASHBOARD_PROXY_PORT", "3457"))
UPSTREAM = f"http://{CONFIG.get('MERIDIAN_LOCAL_HOST', '127.0.0.1')}:{CONFIG.get('MERIDIAN_LOCAL_API_PORT', '3456')}"
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
}


def read_key() -> str:
    env = os.environ.get("MERIDIAN_API_KEY")
    if env:
        return env.strip()
    p = os.path.expanduser("~/.env.local")
    try:
        text = open(p, "r", encoding="utf-8").read()
    except FileNotFoundError:
        raise SystemExit(f"MERIDIAN_API_KEY not found; {p} is missing")
    m = re.search(r"^(?:export\s+)?MERIDIAN_API_KEY=(.*)$", text, re.MULTILINE)
    if not m:
        raise SystemExit(f"MERIDIAN_API_KEY not found in {p}")
    val = m.group(1).strip()
    if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
        val = val[1:-1]
    if not val:
        raise SystemExit("MERIDIAN_API_KEY is empty")
    return val


API_KEY = read_key()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self): self.forward()
    def do_POST(self): self.forward()
    def do_PUT(self): self.forward()
    def do_PATCH(self): self.forward()
    def do_DELETE(self): self.forward()
    def do_OPTIONS(self): self.forward()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    def forward(self):
        length = int(self.headers.get("content-length") or "0")
        body = self.rfile.read(length) if length else None
        url = UPSTREAM + self.path
        headers = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in HOP_BY_HOP or lk in {"host", "content-length", "x-api-key", "authorization"}:
                continue
            headers[k] = v
        headers["x-api-key"] = API_KEY
        headers["Host"] = UPSTREAM.removeprefix("http://")

        req = urllib.request.Request(url, data=body, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.copy_headers(resp.headers, len(data))
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.copy_headers(e.headers, len(data))
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            msg = (f"Dashboard proxy could not reach Meridian tunnel on {UPSTREAM}: {e}").encode()
            self.send_response(502)
            self.send_header("content-type", "text/plain; charset=utf-8")
            self.send_header("content-length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def copy_headers(self, src, content_length: int):
        seen_length = False
        for k, v in src.items():
            lk = k.lower()
            if lk in HOP_BY_HOP:
                continue
            if lk == "content-length":
                seen_length = True
                v = str(content_length)
            self.send_header(k, v)
        if not seen_length:
            self.send_header("content-length", str(content_length))


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    httpd = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"Meridian dashboard proxy listening on http://{LISTEN_HOST}:{LISTEN_PORT} -> {UPSTREAM}", flush=True)
    httpd.serve_forever()
