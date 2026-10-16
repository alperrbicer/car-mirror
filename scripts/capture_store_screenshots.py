#!/usr/bin/env python3
"""Serve original demo media and synthetic IPTV accounts for ProductUITests.

Run this while taking screenshots, then stop it. No provider data is used and
the fixture is never added to the shipping application.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
import json
import os
import re
import time

ROOT = Path(__file__).resolve().parents[1]
PORT = int(os.environ.get("MIRIVO_FIXTURE_PORT", "8769"))
PLAYLIST = ("#EXTM3U\n" + "".join(
    f'#EXTINF:-1 group-title="Mirivo Demo",Mirivo Demo {i:02}\n'
    f"http://127.0.0.1:{PORT}/demo.mp4?clip={i}\n" for i in range(1, 7)
)).encode()
VIDEO = (ROOT / "Resources/ConnectionProbe.mp4").read_bytes()
SERIES_SYNOPSIS = ("Bir kıyı kasabasında yolları kesişen üç arkadaş, geçmişten gelen sırlarla yüzleşir. "
                   "Yıllar sonra gelen bir mektup onları yeniden bir araya getirir. Eski dostluklar sınanırken "
                   "her biri ailesi ve geleceği hakkında zor kararlar vermek zorunda kalır. Kasabanın sakin "
                   "görünümünün ardındaki hikâyeyi birlikte ortaya çıkarırlar.")
CATALOG = ("#EXTM3U\n" + "".join(
    f'#EXTINF:-1 tvg-logo="http://127.0.0.1:{PORT}/catalog/art/{art}.png{f"?episode={number}" if kind == "series" else ""}" group-title="{group}",{title}\n'
    f'http://127.0.0.1:{PORT}/{kind}/artwork/fixture/{number}.{extension}\n'
    for number, title, group, art, kind, extension in [
        (1, "Nova TV", "TR: Ulusal", "nova", "live", "m3u8"),
        (2, "Haber 24", "TR: Ulusal", "news", "live", "m3u8"),
        (3, "Arena Spor", "TR: Spor", "arena", "live", "m3u8"),
        (4, "Spor Plus", "TR: Spor", "nova", "live", "m3u8"),
        (101, "Mavi Yolculuk", "FİLM: Macera", "voyage", "movie", "mp4"),
        (102, "Yolun Ötesi", "FİLM: Macera", "beyond", "movie", "mp4"),
        (103, "Son Işık", "FİLM: Drama", "light", "movie", "mp4"),
        (104, "Eksik Görsel", "Diğer", "missing", "movie", "mp4"),
        (105, "Bilgi Bağlantısı Hatası", "Diğer", "missing", "movie", "mp4"),
        (210, "Kıyı Hikâyeleri S01-E10", "DİZİ: Exxen", "voyage", "series", "mp4"),
        (221, "Kıyı Hikâyeleri S02-E01", "DİZİ: Exxen", "voyage", "series", "mp4"),
        (202, "Kıyı Hikâyeleri S01-E02", "DİZİ: Exxen", "voyage", "series", "mp4"),
        (201, "Kıyı Hikâyeleri S01-E01", "DİZİ: Exxen", "voyage", "series", "mp4"),
        (304, "Gece Vardiyası S02-E04", "DİZİ: Exxen", "light", "series", "mp4"),
        (301, "Gece Vardiyası S01-E01", "DİZİ: Exxen", "light", "series", "mp4"),
    ]
)).encode()


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
        if path == "/favorite-lists.m3u":
            data = CATALOG + (f'#EXTINF:-1 group-title="RADYO: Müzik",Kıyı Radyo\n'
                              f'http://127.0.0.1:{PORT}/radio/favorite.mp3\n').encode()
            mime = "application/vnd.apple.mpegurl"
        elif path == "/live-picker.m3u":
            count = min(15348, max(4, int(parse_qs(request.query).get("count", ["4"])[0])))
            # Finite local clips with live route metadata exercise channel UI
            # without depending on a provider or an external broadcast.
            extra = "".join(
                f'#EXTINF:-1 group-title="Grup {i % 15 + 1:02}",Kanal {i:05}\n'
                f'http://127.0.0.1:{PORT}/live/artwork/fixture/{i}.mp4\n'
                for i in range(5, count + 1)
            ).encode()
            data = CATALOG.replace(b".m3u8", b".mp4") + extra
            mime = "application/vnd.apple.mpegurl"
        elif path.startswith("/live/artwork/fixture/") and path.endswith(".mp4"):
            data, mime = VIDEO, "video/mp4"
        elif path in ["/catalog/get.php", "/catalog.m3u", "/catalog-movie-episodes.m3u", "/catalog-single-season.m3u"]:
            data = CATALOG.replace(b"/series/artwork/fixture/", b"/movie/artwork/fixture/") if path == "/catalog-movie-episodes.m3u" else CATALOG
            if path == "/catalog-single-season.m3u":
                data = re.sub(rb"#EXTINF:[^\n]* S02-E\d+\n[^\n]+\n", b"", data)
            mime = "application/vnd.apple.mpegurl"
        elif path in ["/catalog/player_api.php", "/player_api.php"]:
            query = parse_qs(request.query)
            if query.get("action") == ["get_vod_info"]:
                if query.get("vod_id") == ["105"]:
                    self.send_error(503)
                    return
                info = {"plot": None, "movie_image": f"http://127.0.0.1:{PORT}/catalog/art/beyond.png", "genre": "Macera, Drama", "releasedate": "2025-06-01", "duration_secs": "6540", "rating": "8.2",
                        "director": "Deniz Örnek", "cast": "Ada Örnek, Ege Örnek"}
                details = {"stream_id": 101, "description": "İki kardeş, yıllar sonra kıyı kasabalarında yeniden buluşur. Eski bir yelkenliyle çıktıkları yolculuk, onları unutulmuş hikâyelere ve yeni başlangıçlara götürür."}
                data = json.dumps({"info": info, "movie_data": details} if query.get("vod_id") == ["101"] else {"info": {}}).encode()
            elif query.get("action") == ["get_series"]:
                data = json.dumps([
                    {"series_id": 500, "name": "Kiyi Hikayeleri", "plot": SERIES_SYNOPSIS, "genre": "Drama", "releaseDate": "2024-01-26"},
                    {"series_id": 600, "name": "Gece Vardiyası", "plot": "Gece çalışan bir ekip, şehrin sessiz saatlerinde yeni hikâyeler keşfeder."},
                ]).encode()
            elif query.get("action") == ["get_series_info"]:
                if query.get("series_id") == ["500"]:
                    info = {"plot": SERIES_SYNOPSIS, "cover": f"http://127.0.0.1:{PORT}/catalog/art/light.png", "genre": "Drama", "releaseDate": "2024-01-26", "rating": "7.9", "director": "Deniz Örnek", "cast": "Ada Örnek, Ege Örnek"}
                    episodes = {"1": [
                        {"id": "201", "description": "Kasabaya dönen bir mektup, üç arkadaşın hayatını değiştirir.", "info": {"plot": None, "duration_secs": 1980}},
                        {"id": "202", "info": {"duration_secs": 2040}},
                        {"id": "210", "info": {}},
                    ], "2": [{"id": "221", "info": {}}]}
                else:
                    info = {"plot": "Gece çalışan bir ekip, şehrin sessiz saatlerinde yeni hikâyeler keşfeder."}
                    episodes = {"1": [{"id": "301", "info": {}}], "2": [{"id": "304", "info": {}}]}
                data = json.dumps({"info": info, "episodes": episodes}).encode()
            else:
                data = json.dumps({"user_info": {"auth": 1, "status": "Active", "exp_date": None}}).encode()
            mime = "application/json"
        elif path.startswith("/catalog/art/"):
            artwork = ROOT / "build/library-artwork-fixtures" / Path(path).name
            if not artwork.is_file():
                self.send_error(404)
                return
            data, mime = artwork.read_bytes(), "image/png"
        elif path.startswith(("/movie/artwork/fixture/", "/series/artwork/fixture/")):
            if path.startswith("/series/") or Path(path).stem in {"201", "202", "210", "221", "301", "304"}:
                fixture = ROOT / "build/playback-options-fixtures/options.mp4"
                if not fixture.is_file():
                    self.send_error(404)
                    return
                data = fixture.read_bytes()
            else:
                data = VIDEO
            mime = "video/mp4"
        elif path == "/sources/get.php":
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
            if path == "/demo.m3u" and parse_qs(request.query).get("long") == ["1"]:
                data = PLAYLIST.replace(b"/demo.mp4", b"/tracks/options.mp4")
        elif path == "/demo.mp4":
            data, mime = VIDEO, "video/mp4"
        elif path in ["/tracks/options.mp4", "/tracks/options.mkv"]:
            fixture = ROOT / "build/playback-options-fixtures" / Path(path).name
            if not fixture.is_file():
                self.send_error(404)
                return
            data, mime = fixture.read_bytes(), "video/mp4" if fixture.suffix == ".mp4" else "video/x-matroska"
        else:
            self.send_error(404)
            return
        if path in ["/tracks/options.mp4", "/tracks/options.mkv"]:
            # Exercise cold-launch restoration while the first network requests
            # and seek ranges arrive after the player view is already visible.
            delay = parse_qs(request.query).get("delay", ["0"])[0]
            if delay in ["0", "1", "2"]:
                time.sleep(int(delay))
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
            try:
                self.wfile.write(data[start:end + 1])
            except (BrokenPipeError, ConnectionResetError):
                pass  # Players cancel an old range request when seeking.


if __name__ == "__main__":
    print(f"Mirivo screenshot fixture: http://127.0.0.1:{PORT}/demo.m3u", flush=True)
    # MKV can seek to its cue index while an earlier range is still open.
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
