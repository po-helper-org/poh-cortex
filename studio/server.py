"""HTTP Студии Кортекса: статика страницы и JSON API. Запуск — `bin/cortex serve` (см. docs/studio.md).

  GET  /api/overview                 книга: организация, главы, недавнее, протухшее, здоровье
  GET  /api/chapter?slug=            глава: введение и узлы (slug=decide — слой решений)
  GET  /api/node?id=                 узел: шапка, текст, связи, обратные связи, находки гейта
  GET  /api/search?q=                поиск тем же индексом, что `cortex ask`
  GET  /api/queue                    очередь разбора: записи _intake, черновики агентов, схема для формы
  GET  /api/journal?days=30          изменения памяти по дням (git)
  GET  /api/health                   здоровье памяти (`cortex health --json`)
  GET  /api/me                       кто смотрит и может ли писать
  POST /api/queue/<id>/accept        запись очереди → узел
  POST /api/queue/<id>/reject        {reason?}
  POST /api/drafts/<node_id>/accept|reject

Кто может писать. Студия не хранит пароли: имя человека даёт прокси перед ней (`--user-header`, например
`X-Forwarded-User` или `X-authentik-username`), список владельцев — `--owners`. Без `--owners` писать можно только
при запуске на localhost (один человек на своей машине). `--read-only` выключает запись совсем. Каждый POST требует
заголовок `X-Cortex-Studio: 1` — форма чужого сайта его не пошлёт.
"""
from __future__ import annotations

import ipaddress
import json
import mimetypes
import pathlib
import re
import sys
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .core import Refused, Vault

STATIC = pathlib.Path(__file__).resolve().parent / "static"
BODY_LIMIT = 64 * 1024
_QUEUE = re.compile(r"^/api/queue/([0-9a-f]{12})/(accept|reject)$")
_DRAFT = re.compile(r"^/api/drafts/([a-z0-9][a-z0-9._-]{0,79})/(accept|reject)$")
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; "
       "frame-ancestors 'self'; form-action 'none'; base-uri 'none'")


def is_loopback(host: str) -> bool:
    if host in ("localhost", ""):
        return host == "localhost"
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


class Settings:
    def __init__(self, vault: Vault, read_only=False, owners=(), user_header="", local=True, base=""):
        self.vault, self.read_only, self.local = vault, read_only, local
        self.owners = {o.strip() for o in owners if o and o.strip()}
        self.user_header = user_header.strip()
        self.base = "/" + base.strip("/") if base.strip("/") else ""

    def who(self, headers) -> str:
        return (headers.get(self.user_header) or "").strip()[:80] if self.user_header else ""

    def may_write(self, headers) -> tuple[bool, str]:
        if self.read_only:
            return False, "студия запущена только для чтения (--read-only)"
        if self.owners:
            who = self.who(headers)
            return (who in self.owners,
                    "" if who in self.owners else f"писать могут только владельцы памяти; вы — {who or 'не вошли'}")
        if self.local:
            return True, ""
        return False, "не задан --owners: вне localhost запись выключена"


def make_handler(cfg: Settings, quiet: bool = False):
    class Handler(BaseHTTPRequestHandler):
        server_version = "cortex-studio"
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # журнал — коротко, в stderr
            if not quiet:
                sys.stderr.write("studio: " + (fmt % args) + "\n")

        # ─── ответы ───
        def _send(self, status: int, body: bytes, ctype: str, extra=None):
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", CSP)
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _json(self, status: int, data):
            self._send(status, json.dumps(data, ensure_ascii=False, default=str).encode("utf-8"),
                       "application/json; charset=utf-8", {"Cache-Control": "no-store"})

        def _path(self) -> tuple[str, dict]:
            url = urllib.parse.urlsplit(self.path)
            path = url.path
            if cfg.base:
                if path == cfg.base:
                    path = "/"
                elif path.startswith(cfg.base + "/"):
                    path = path[len(cfg.base):]
            return path, {k: v[-1] for k, v in urllib.parse.parse_qs(url.query).items()}

        # ─── чтение ───
        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            if cfg.base and urllib.parse.urlsplit(self.path).path == cfg.base:
                return self._send(301, b"", "text/plain", {"Location": cfg.base + "/"})
            path, q = self._path()
            try:
                if path.startswith("/api/"):
                    return self._json(200, self._get_api(path, q))
                return self._static(path)
            except Refused as e:
                return self._json(e.status, e.body())
            except Exception:  # noqa: BLE001
                traceback.print_exc()
                return self._json(500, {"ok": False, "error": "internal", "message": "ошибка студии — см. журнал"})

        def _get_api(self, path: str, q: dict):
            v = cfg.vault
            if path == "/api/overview":
                return v.overview()
            if path == "/api/chapter":
                return v.chapter(q.get("slug", ""))
            if path == "/api/node":
                return v.node(q.get("id", ""))
            if path == "/api/search":
                return v.search(q.get("q", ""))
            if path == "/api/queue":
                return v.queue()
            if path == "/api/journal":
                try:
                    days = int(q.get("days", 30))
                except ValueError:
                    days = 30
                return v.journal(days)
            if path == "/api/health":
                return v.health()
            if path == "/api/me":
                ok, why = cfg.may_write(self.headers)
                return {"user": cfg.who(self.headers), "can_write": ok, "why": why, "commit": v.commit_enabled}
            raise Refused(404, "not_found", "нет такого адреса API")

        def _static(self, path: str):
            name = path.lstrip("/") or "index.html"
            if "/" in name or name.startswith("."):
                name = "index.html"   # адреса страницы (#/…) отдаёт одна страница
            f = STATIC / name
            if not f.is_file():
                f = STATIC / "index.html"
            ctype = mimetypes.guess_type(f.name)[0] or "application/octet-stream"
            if ctype.startswith("text/") or ctype in ("application/javascript",):
                ctype += "; charset=utf-8"
            self._send(200, f.read_bytes(), ctype, {"Cache-Control": "no-cache"})

        # ─── запись ───
        def do_POST(self):
            path, _ = self._path()
            try:
                if self.headers.get("X-Cortex-Studio") != "1":
                    raise Refused(403, "csrf", "нет заголовка X-Cortex-Studio")
                ok, why = cfg.may_write(self.headers)
                if not ok:
                    raise Refused(403, "read_only", why)
                size = int(self.headers.get("Content-Length") or 0)
                if size > BODY_LIMIT:
                    raise Refused(413, "too_large", "запрос больше 64 КБ")
                raw = self.rfile.read(size) if size else b"{}"
                try:
                    body = json.loads(raw or b"{}")
                except ValueError:
                    raise Refused(400, "invalid", "тело — JSON") from None
                if not isinstance(body, dict):
                    raise Refused(400, "invalid", "тело — JSON-объект")
                who = cfg.who(self.headers)
                m = _QUEUE.match(path)
                if m:
                    fn = cfg.vault.accept if m[2] == "accept" else cfg.vault.reject
                    return self._json(200, fn(m[1], body, who))
                m = _DRAFT.match(path)
                if m:
                    return self._json(200, cfg.vault.draft(m[1], m[2], who))
                raise Refused(404, "not_found", "нет такого адреса API")
            except Refused as e:
                return self._json(e.status, e.body())
            except Exception:  # noqa: BLE001
                traceback.print_exc()
                return self._json(500, {"ok": False, "error": "internal", "message": "ошибка студии — см. журнал"})

    return Handler


def serve(root: pathlib.Path, host="127.0.0.1", port=8765, read_only=False, owners=(), user_header="",
          commit=False, base="") -> int:
    local = is_loopback(host)
    if not local and not read_only and not owners:
        print("✗ студия слушает не localhost: задайте --owners и --user-header (имя входа от прокси) "
              "или запустите с --read-only", file=sys.stderr)
        return 2
    if owners and not user_header:
        print("✗ --owners без --user-header: имя входа студии даёт прокси, укажите его заголовок", file=sys.stderr)
        return 2
    cfg = Settings(Vault(root, commit=commit), read_only, owners, user_header, local, base)
    httpd = ThreadingHTTPServer((host, port), make_handler(cfg))
    mode = "только чтение" if read_only else ("запись: " + ", ".join(sorted(cfg.owners)) if cfg.owners
                                              else "запись: этот компьютер")
    print(f"Студия Кортекса: http://{host}:{httpd.server_address[1]}{cfg.base}/  ·  {root}  ·  {mode}"
          + ("  ·  коммит каждого решения" if commit else ""), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0
