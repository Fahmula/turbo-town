#!/usr/bin/env python3
"""A stand-in for GitHub Releases, for testing turbotown.sh and the in-game updater.

    python3 tools/steamdeck/fake_github.py <releases_dir> [--throttle-kbps N]

<releases_dir> holds one folder per release (v0.12.0/...) with its files, a
`latest` file naming the latest tag, and optionally `<tag>/notes.md` (the
release notes) and `api_status` (an HTTP status the API should answer with,
like 403 for "rate limited"). They're read on every request, so a test can
change them while the server runs. It listens on 127.0.0.1 on a free port,
writes the port to <releases_dir>/port and logs requests to requests.log.

Routes (the same paths as github.com and api.github.com):
    /releases/latest                         302 to /releases/tag/<latest>
    /releases/tag/<tag>                      200
    /releases/download/<tag>/<file>          the file
    /repos/<owner>/<repo>/releases/latest    the API's JSON, with download URLs here
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
THROTTLE = 0
if "--throttle-kbps" in sys.argv:
    THROTTLE = int(sys.argv[sys.argv.index("--throttle-kbps") + 1])
LOG_LOCK = threading.Lock()


def read(name, default=""):
    try:
        return (ROOT / name).read_text().strip()
    except OSError:
        return default


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        with LOG_LOCK, open(ROOT / "requests.log", "a") as f:
            f.write("%s %s\n" % (self.command, self.path))

    def _send(self, code, body=b"", ctype="text/plain", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?")[0]
        parts = [p for p in path.split("/") if p]
        latest = read("latest")
        if path == "/releases/latest":
            if not latest:
                return self._send(404, b"no release")
            return self._send(302, headers={"Location": "/releases/tag/" + latest})
        if len(parts) == 3 and parts[:2] == ["releases", "tag"]:
            return self._send(200, b"release page")
        if len(parts) == 4 and parts[:2] == ["releases", "download"]:
            return self._file(ROOT / parts[2] / parts[3])
        if len(parts) == 5 and parts[0] == "repos" and parts[3:] == ["releases", "latest"]:
            status = int(read("api_status", "200") or 200)
            if status != 200:
                return self._send(status, b'{"message": "fake error"}', "application/json")
            if not latest:
                return self._send(404, b'{"message": "Not Found"}', "application/json")
            host = "http://127.0.0.1:%d" % self.server.server_port
            assets = [
                {"name": f.name, "size": f.stat().st_size,
                 "browser_download_url": "%s/releases/download/%s/%s" % (host, latest, f.name)}
                for f in sorted((ROOT / latest).iterdir()) if f.is_file() and f.name != "notes.md"
            ]
            body = {"tag_name": latest, "name": "Turbo Town " + latest, "draft": False,
                    "prerelease": False, "body": read(latest + "/notes.md"), "assets": assets}
            return self._send(200, json.dumps(body).encode(), "application/json")
        self._send(404, b"not found")

    def _file(self, f):
        if not f.is_file() or ROOT not in f.resolve().parents:
            return self._send(404, b"not found")
        size = f.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(f, "rb") as src:
            while True:
                chunk = src.read(64 * 1024)
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                if THROTTLE:
                    time.sleep(len(chunk) / (THROTTLE * 1024.0))


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
(ROOT / "port").write_text(str(server.server_port))
print("fake GitHub on port %d serving %s" % (server.server_port, ROOT), flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
