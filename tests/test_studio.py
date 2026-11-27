"""Студия Кортекса (`bin/cortex serve`): API на временной копии vault. Только стандартная библиотека.

    python3 -m unittest discover -s tests
"""
from __future__ import annotations

import datetime
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from studio.core import Vault, record_id  # noqa: E402
from studio.server import Settings, make_handler, serve  # noqa: E402

TODAY = datetime.date(2026, 11, 27)
RELAY = """---
captured_by: "hermes:po-a"
date: 2026-11-20
title: "Биллинг меняет схему тарифов с января"
author: "Иван, архитектор"
authority: ""
channel: chat
link: TASK-12
nexus_hint: product
type_hint: feature
---
С января биллинг переходит на поминутные тарифы, старый API отключат в марте.
"""
OWNER = """---
captured_by: human
date: 2026-11-25
title: "Владелец CRM — Мария"
author: "Мария"
authority: "Мария"
channel: email
link: https://mail.example/msg/1
---
CRM ведёт Мария, вопросы интеграции — к ней.
"""
BROKEN = "просто текст без шапки\n"


def git(root, *a):
    return subprocess.run(["git", "-C", str(root), *a], capture_output=True, text=True, check=True).stdout


class Studio(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="cortex-studio-"))
        self.root = self.tmp / "vault"
        shutil.copytree(ROOT / "GROUND", self.root / "GROUND")
        intake = self.root / "GROUND" / "_intake"
        (intake / "hermes" / "po-a").mkdir(parents=True, exist_ok=True)
        (intake / "hermes" / "po-a" / "2026-11-20-relay.md").write_text(RELAY, encoding="utf-8")
        (intake / "people").mkdir(exist_ok=True)
        (intake / "people" / "2026-11-25-owner.md").write_text(OWNER, encoding="utf-8")
        (intake / "people" / "2026-11-26-broken.md").write_text(BROKEN, encoding="utf-8")
        git(self.root, "init", "-q")
        git(self.root, "add", "-A")
        git(self.root, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
        self.start()

    def start(self, **kw):
        if getattr(self, "httpd", None):
            self.stop()
        vault = Vault(self.root, commit=kw.pop("commit", True), today=TODAY)
        cfg = Settings(vault, kw.get("read_only", False), kw.get("owners", ()), kw.get("user_header", ""),
                       kw.get("local", True), kw.get("base", ""))
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(cfg, quiet=True))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.httpd = None

    def tearDown(self):
        self.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def call(self, path, body=None, headers=None, studio=True):
        h = dict(headers or {})
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            h["Content-Type"] = "application/json"
            if studio:
                h["X-Cortex-Studio"] = "1"
        req = urllib.request.Request(self.base + path, data=data, headers=h, method="POST" if data else "GET")
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if r.headers.get_content_type() == "application/json" else raw)
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")

    def item(self, path_part):
        _, q = self.call("/api/queue")
        return next(x for x in q["items"] if path_part in x["path"])

    def gate_errors(self):
        r = subprocess.run([sys.executable, str(ROOT / "bin" / "cortex"), "--root", str(self.root), "gate"],
                           capture_output=True, text=True)
        return r.returncode

    # ─── чтение ───
    def test_overview_lists_chapters_and_health(self):
        code, o = self.call("/api/overview")
        self.assertEqual(code, 200)
        slugs = [c["slug"] for c in o["chapters"]]
        self.assertIn("product", slugs)
        self.assertIn("ops-model", slugs)
        self.assertEqual(o["health"]["intake"]["count"], 3)
        self.assertFalse(o["org"]["configured"], "в шаблоне организация не заполнена")

    def test_chapter_node_search(self):
        code, c = self.call("/api/chapter?slug=ops-model")
        self.assertEqual(code, 200)
        self.assertTrue(c["nodes"])
        nid = c["nodes"][0]["id"]
        code, n = self.call("/api/node?id=" + nid)
        self.assertEqual(code, 200)
        self.assertEqual(n["id"], nid)
        self.assertIn("backlinks", n)
        self.assertEqual(self.call("/api/node?id=nope")[0], 404)
        self.assertEqual(self.call("/api/chapter?slug=nope")[0], 404)
        code, s = self.call("/api/search?q=" + urllib.request.quote("делегирования"))
        self.assertEqual(code, 200)
        self.assertTrue(s["hits"])

    def test_static_page_and_spa_fallback(self):
        code, raw = self.call("/")
        self.assertEqual(code, 200)
        self.assertIn(b"app.js", raw)
        self.assertEqual(self.call("/chapter/product")[0], 200)

    def test_base_prefix_behind_proxy(self):
        self.start(base="/cortex")
        self.assertEqual(self.call("/cortex/api/overview")[0], 200)
        self.assertIn(b"app.js", self.call("/cortex/")[1])

    def test_journal_from_git(self):
        code, j = self.call("/api/journal?days=3650")
        self.assertEqual(code, 200)
        self.assertEqual(j["entries"][0]["subject"], "init")

    # ─── очередь: потолки ───
    def test_ceilings_from_ladder(self):
        relay = self.item("relay")
        self.assertTrue(relay["ceiling"]["relay"])
        self.assertEqual(relay["ceiling"]["cp_max"], 2, "пересказ сборщика без authority — не выше 2")
        owner = self.item("owner")
        self.assertFalse(owner["ceiling"]["relay"])
        self.assertEqual(owner["ceiling"]["cp_max"], 9, "письмо владельца — без потолка канала")
        self.assertIn("error", self.item("broken"))

    def test_accept_over_ceiling_refused(self):
        relay = self.item("relay")
        code, r = self.call(f"/api/queue/{relay['id']}/accept", {"cp": 5})
        self.assertEqual(code, 422)
        self.assertEqual(r["error"], "ceiling")
        self.assertTrue((self.root / relay["path"]).exists(), "отказ ничего не трогает")

    def test_own_artifact_lifts_ceiling(self):
        relay = self.item("relay")
        code, r = self.call(f"/api/queue/{relay['id']}/accept",
                            {"cp": 6, "sources": ["https://wiki.example/billing-2027"]})
        self.assertEqual(code, 200, r)

    def test_accept_creates_node_logs_and_commits(self):
        relay = self.item("relay")
        code, r = self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2, "title": "Биллинг: поминутные тарифы с января"})
        self.assertEqual(code, 200, r)
        node = self.root / r["path"]
        text = node.read_text(encoding="utf-8")
        self.assertIn("status: accepted", text)
        self.assertIn("captured_by: human", text)
        self.assertIn("intake_by: ", text)
        self.assertIn("TASK-12", text)
        self.assertFalse((self.root / relay["path"]).exists(), "запись очереди удалена")
        log = (self.root / "GROUND/DECIDE/log/2026-11.md").read_text(encoding="utf-8")
        self.assertIn("#" + relay["hash"], log)
        self.assertTrue(r["commit"])
        files = git(self.root, "show", "--name-only", "--format=", "HEAD").split()
        self.assertEqual(sorted(files), sorted([r["path"], "GROUND/DECIDE/log/2026-11.md", relay["path"]]))
        self.assertEqual(self.gate_errors(), 0, "гейт зелёный после приёмки")
        _, n = self.call("/api/node?id=" + r["node"])
        self.assertEqual(n["status"], "accepted")
        self.assertEqual(self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2})[0], 404, "дважды не принять")

    def test_commit_only_touched_paths(self):
        stray = self.root / "GROUND" / "NEXUS" / "product" / "stray.md"
        stray.write_text("чужой файл агента\n", encoding="utf-8")
        relay = self.item("relay")
        self.assertEqual(self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2})[0], 200)
        self.assertNotIn("stray.md", git(self.root, "show", "--name-only", "--format=", "HEAD"))
        self.assertIn("stray.md", git(self.root, "status", "--short"))

    def test_accept_wrong_type_refused(self):
        relay = self.item("relay")
        code, r = self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2, "type": "vydumka"})
        self.assertEqual(code, 400)
        self.assertEqual(r["field"], "type")

    def test_reject_logs_and_removes(self):
        owner = self.item("owner")
        code, r = self.call(f"/api/queue/{owner['id']}/reject", {"reason": "уже известно"})
        self.assertEqual(code, 200, r)
        self.assertFalse((self.root / owner["path"]).exists())
        log = (self.root / "GROUND/DECIDE/log/2026-11.md").read_text(encoding="utf-8")
        self.assertIn("отклонено: уже известно", log)
        self.assertIn("#" + owner["hash"], log)

    def test_broken_record_rejectable_not_acceptable(self):
        broken = self.item("broken")
        self.assertEqual(self.call(f"/api/queue/{broken['id']}/accept", {"cp": 2})[0], 400)
        self.assertEqual(self.call(f"/api/queue/{broken['id']}/reject", {})[0], 200)

    def test_secret_like_refused(self):
        relay = self.item("relay")
        code, r = self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2, "body": "пароль: hunter2"})
        self.assertEqual(code, 400)

    # ─── черновики ───
    def test_draft_accept_via_cortex_review(self):
        r = subprocess.run([sys.executable, str(ROOT / "bin" / "cortex"), "--root", str(self.root), "node", "new",
                            "--nexus", "product", "--type", "feature", "--title", "Черновик агента про оплату",
                            "--source", "TASK-7", "--by", "hermes:po-a"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        _, q = self.call("/api/queue")
        draft = next(d for d in q["drafts"] if "оплату" in d["title"])
        code, out = self.call(f"/api/drafts/{draft['id']}/accept", {})
        self.assertEqual(code, 200, out)
        self.assertIn("status: accepted", (self.root / draft["path"]).read_text(encoding="utf-8"))
        self.assertEqual(self.call(f"/api/drafts/{draft['id']}/accept", {})[0], 404)

    # ─── кто может писать ───
    def test_post_requires_studio_header(self):
        relay = self.item("relay")
        code, r = self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2}, studio=False)
        self.assertEqual(code, 403)
        self.assertEqual(r["error"], "csrf")

    def test_read_only(self):
        self.start(read_only=True)
        relay = self.item("relay")
        self.assertEqual(self.call(f"/api/queue/{relay['id']}/accept", {"cp": 2})[0], 403)
        self.assertFalse(self.call("/api/me")[1]["can_write"])

    def test_owners_by_proxy_header(self):
        self.start(owners=["maria"], user_header="X-Forwarded-User", local=False)
        relay = self.item("relay")
        self.assertEqual(self.call(f"/api/queue/{relay['id']}/reject", {}, {"X-Forwarded-User": "ivan"})[0], 403)
        code, r = self.call(f"/api/queue/{relay['id']}/reject", {}, {"X-Forwarded-User": "maria"})
        self.assertEqual(code, 200, r)
        self.assertIn("решил maria", (self.root / "GROUND/DECIDE/log/2026-11.md").read_text(encoding="utf-8"))

    def test_public_bind_without_owners_refuses_to_start(self):
        self.assertEqual(serve(self.root, host="0.0.0.0", port=0), 2)

    def test_record_id_is_path_hash(self):
        relay = self.item("relay")
        self.assertEqual(relay["id"], record_id(relay["path"]))


if __name__ == "__main__":
    unittest.main()
