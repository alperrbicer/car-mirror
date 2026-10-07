#!/usr/bin/env python3
"""Serve original demo media and synthetic IPTV accounts for ProductUITests.

Run this while taking screenshots, then stop it. No provider data is used and
the fixture is never added to the shipping application.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
import json
import re

ROOT = Path(__file__).resolve().parents[1]
PLAYLIST = ("#EXTM3U\n" + "".join(
    f'#EXTINF:-1 group-title="Mirivo Demo",Mirivo Demo {i:02}\n'
    f"http://127.0.0.1:8769/demo.mp4?clip={i}\n" for i in range(1, 7)
)).encode()
VIDEO = (ROOT / "Resources/ConnectionProbe.mp4").read_bytes()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Request URLs may contain synthetic account credentials; do not log them.
        pass

    def do_HEAD(self):
        self.serve(False)

    def do_GET(self):
        self.serve(True)

    def serve(self, body):
        request = urlsplit(self.path)
        path = request.path
        if path == "/sources/get.php":
            query = parse_qs(request.query)
            if query.get("username") != ["source+user"] or query.get("password") != ["source+p&ss"]:
                self.send_error(401)
                return
            data, mime = PLAYLIST, "application/vnd.apple.mpegurl"
        elif path == "/sources/invalid/get.php":
            data, mime = b'{"user_info":{"auth":0}}', "application/json"
        elif path == "/expiry/player_api.php":
            user = parse_qs(request.query).get("username", [""])[0]
            if user == "expiry-error":
                self.send_error(503)
                return
            info = {"auth": 1, "status": "Active", "exp_date": "4102488000"}
            if user == "expiry-expired":
                info.update(status="Expired", exp_date=1700000000)
            elif user == "expiry-unknown":
                info["exp_date"] = None
            data, mime = json.dumps({"user_info": info}).encode(), "application/json"
        elif path in ["/demo.m3u", "/expiry/get.php"]:
            data, mime = PLAYLIST, "application/vnd.apple.mpegurl"
        elif path == "/demo.mp4":
            data, mime = VIDEO, "video/mp4"
        else:
            self.send_error(404)
            return
        start, end, status = 0, len(data) - 1, 200
        value = self.headers.get("Range")
        if value:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", value)
            if not match or not any(match.groups()):
                self.send_error(416)
                return
            first, last = match.groups()
            if first:
                start = int(first)
                end = min(int(last), end) if last else end
            else:
                start = max(0, len(data) - int(last))
            if start > end:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(data)}")
                self.end_headers()
                return
            status = 206
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.end_headers()
        if body:
            self.wfile.write(data[start:end + 1])


if __name__ == "__main__":
    print("Mirivo screenshot fixture: http://127.0.0.1:8769/demo.m3u", flush=True)
    HTTPServer(("127.0.0.1", 8769), Handler).serve_forever()
