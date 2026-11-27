"""Студия Кортекса: чтение памяти для страницы и разбор очереди. HTTP — в server.py.

Память читается тем же кодом, что и `bin/cortex` (модуль грузится из файла инструмента): схема, узлы, свежесть,
распад CP, поиск, гейт и здоровье считаются одинаково в терминале и на странице. Пишет студия только через
`bin/cortex` (`node new`, `review`) и в два места сама — строка журнала разбора `GROUND/DECIDE/log/<ГГГГ-ММ>.md` и
удаление разобранной записи очереди. Новый узел, на котором гейт дал ERROR, откатывается.

Потолок CP при приёмке — из `GROUND/SCHEMA/ladder.yaml`: канал записи (`ceilings.channel`), пересказ сборщика
(`captured_by` не human, authority пуст или не автор — `ceilings.authority.not_owner`). Выше потолка — только со
своим артефактом-источником, отличным от ссылки записи.
"""
from __future__ import annotations

import datetime
import hashlib
import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import threading
from importlib.machinery import SourceFileLoader

TOOL_ROOT = pathlib.Path(__file__).resolve().parent.parent
BIN = TOOL_ROOT / "bin" / "cortex"

INTAKE_SKIP = ("README.md", "inbox.md", "_template.md")
SUMMARY_MAX = 220
TITLE_MAX, FIELD_MAX, BODY_MAX, REASON_MAX, SOURCE_MAX = 200, 120, 4000, 300, 300
DEFAULT_CP = 2           # пересказ сборщиком — вторая ступень; выше решает человек
UNKNOWN_CHANNEL_CP = 3   # канал без правила в лестнице — как устное
NODE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{1,63}$")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_LEAD_DATE = re.compile(r"^(\d{4}-\d{2}-\d{2})")
_INBOX_LINE = re.compile(r"^\d{4}-\d{2}-\d{2}\s*\|")
SECRET = re.compile(r"(?i)(password|пароль|passwd|secret|token|api[_-]?key|bearer\s|private key|BEGIN [A-Z ]*KEY|"
                    r"ghp_|github_pat_|xox[bap]-|otpauth://|[?&](token|key|sig|signature|auth|pwd|access_token)=|"
                    r"(?-i:\bsk-[A-Za-z0-9_-]{16,})|\beyJ[A-Za-z0-9_-]{8,}\.eyJ|glpat-|(?-i:\bAKIA[0-9A-Z]{16}\b))")

_core = None
_core_lock = threading.Lock()


def core():
    """Модуль `bin/cortex` — один раз на процесс. Файл без расширения, поэтому загрузчик явный."""
    global _core
    with _core_lock:
        if _core is None:
            loader = SourceFileLoader("cortex_tool", str(BIN))
            spec = importlib.util.spec_from_loader("cortex_tool", loader)
            mod = importlib.util.module_from_spec(spec)
            loader.exec_module(mod)
            _core = mod
    return _core


class Refused(Exception):
    def __init__(self, status: int, code: str, message: str, field: str = ""):
        super().__init__(message)
        self.status, self.code, self.message, self.field = status, code, message, field

    def body(self) -> dict:
        return {"ok": False, "error": self.code, "message": self.message, **({"field": self.field} if self.field else {})}


def _str(v) -> str:
    if v is None:
        return ""
    if isinstance(v, list):
        return ", ".join(_str(x) for x in v)
    return str(v)


def summary(body: str) -> str:
    """Первый абзац текста без заголовков, таблиц, комментариев и кода — для карточки."""
    para: list[str] = []
    fence = False
    for line in (body or "").splitlines():
        s = line.strip()
        if s.startswith("```"):
            fence = not fence
            continue
        if fence or s.startswith(("#", "|", "<!--", "---")):
            if para:
                break
            continue
        if not s:
            if para:
                break
            continue
        para.append(s.lstrip("-*> ").strip())
    text = re.sub(r"[*_`]", "", " ".join(para))
    return text if len(text) <= SUMMARY_MAX else text[:SUMMARY_MAX - 1].rstrip() + "…"


def record_id(rel: str) -> str:
    """id записи очереди в адресе — хэш пути: сам путь в запрос не попадает, `..` подставить нельзя."""
    return hashlib.sha1(rel.encode("utf-8")).hexdigest()[:12]


def hash_of(statement: str) -> str:
    norm = re.sub(r"\s+", " ", str(statement).casefold()).strip(" \t\n.,;:!?\"'«»()[]—–-…")
    return hashlib.sha1(norm.encode("utf-8")).hexdigest()[:10]


def secret_like(*values) -> bool:
    return any(SECRET.search(str(v or "")) for v in values)


def one_line(v) -> str:
    return re.sub(r"\s+", " ", str(v or "")).strip()


class Vault:
    """Один vault Кортекса. Чтение строит память заново на каждый запрос (как CLI): файлы — истина, кеша нет."""

    def __init__(self, root: pathlib.Path, commit: bool = False, today=None):
        self.root = pathlib.Path(root).resolve()
        self.commit_enabled = commit
        self._today = today            # для тестов: фиксированная дата
        self._lock = threading.Lock()  # «Принять» дважды подряд не создаст узел дважды

    # ─── загрузка ───
    def today(self) -> datetime.date:
        return self._today or datetime.date.today()

    def cx(self):
        c = core()
        c.TODAY = self.today()   # сервис живёт дольше суток: дата — на каждый запрос, а не на импорт
        return c.Cortex(self.root)

    # ─── чтение ───
    def _card(self, cx, n) -> dict:
        c = core()
        a = c.anchors(cx, n)
        return {"id": n.id, "title": _str(n.title), "nexus": _str(n["nexus"]), "type": _str(n["node_type"]),
                "scope": _str(a["scope"]), "owner": _str(n["owner"]), "cp": a["cp"], "effective_cp": a["effective_cp"],
                "ripeness": a["ripeness"], "updated": _str(n["updated"]), "status": _str(n["status"]),
                "layer": n.layer, "path": n.rel, "summary": summary(n.body)}

    @staticmethod
    def _countable(n) -> bool:
        return bool(n.id) and n.path.stem not in ("_index", "_registry") and n["status"] != "rejected"

    def overview(self) -> dict:
        c = core()
        cx = self.cx()
        chapters = []
        for slug, meta in cx.nexuses.items():
            nodes = [n for n in cx.nodes if n.layer == "curated" and n["nexus"] == slug and self._countable(n)]
            intro = next((n for n in cx.nodes if n.layer == "curated" and n["nexus"] == slug
                          and n.path.stem == "_index"), None)
            chapters.append({
                "slug": slug, "name": _str(meta.get("name")) or slug, "purpose": _str(meta.get("purpose")),
                "owner": _str(meta.get("owner")), "scope": _str(meta.get("scope")),
                "onboarded": _str(meta.get("onboarded")), "change_rate": _str(meta.get("change_rate")),
                "nodes": len([n for n in nodes if n["status"] != "draft"]),
                "drafts": len([n for n in nodes if n["status"] == "draft"]),
                "wilting": len([n for n in nodes if cx.ripeness_of(n)[0] == "wilting"]),
                "intro": summary(intro.body) if intro else ""})
        decide = [n for n in cx.nodes if n.layer == "decisions" and self._countable(n)]
        curated = [n for n in cx.nodes if n.layer == "curated" and self._countable(n)]
        recent = sorted((n for n in curated + decide if c.as_date(n["updated"])),
                        key=lambda n: (c.as_date(n["updated"]), n.id), reverse=True)[:8]
        stale = sorted((n for n in curated if cx.ripeness_of(n)[0] == "wilting"),
                       key=lambda n: -(cx.ripeness_of(n)[1] or 0))[:10]
        product = cx.config.get("product") if isinstance(cx.config.get("product"), dict) else {}
        return {
            "version": c.VERSION, "today": str(self.today()),
            "org": {"company": _str(cx.config.get("company")), "product": _str(product.get("name")),
                    "idea": one_line(product.get("idea")), "configured": "<" not in _str(cx.config.get("company"))},
            "chapters": chapters,
            "decide": {"nodes": len(decide), "by_type": _counts(_str(n["node_type"]) for n in decide)},
            "totals": {"nodes": len(curated) + len(decide), "chapters": len(chapters)},
            "recent": [self._card(cx, n) for n in recent],
            "stale": [self._card(cx, n) for n in stale],
            "health": c.health(cx),
        }

    def chapter(self, slug: str) -> dict:
        cx = self.cx()
        if slug == "decide":
            nodes = [n for n in cx.nodes if n.layer == "decisions" and self._countable(n)]
            return {"slug": "decide", "name": "Решения и ставки", "purpose": "обещания, решения, доказательства",
                    "intro": "", "nodes": [self._card(cx, n) for n in sorted(nodes, key=lambda n: _str(n.title))]}
        meta = cx.nexuses.get(slug)
        if not meta:
            raise Refused(404, "not_found", f"Нексуса {slug!r} нет в реестре")
        nodes = [n for n in cx.nodes if n.layer == "curated" and n["nexus"] == slug and self._countable(n)]
        intro = next((n for n in cx.nodes if n.layer == "curated" and n["nexus"] == slug
                      and n.path.stem == "_index"), None)
        return {"slug": slug, "name": _str(meta.get("name")) or slug, "purpose": _str(meta.get("purpose")),
                "owner": _str(meta.get("owner")), "onboarded": _str(meta.get("onboarded")),
                "types": list(meta.get("node_types") or []),
                "intro": intro.body.strip() if intro else "", "intro_id": intro.id if intro else "",
                "nodes": [self._card(cx, n) for n in sorted(nodes, key=lambda n: (n["status"] == "draft", _str(n.title)))]}

    def node(self, nid: str) -> dict:
        c = core()
        cx = self.cx()
        n = cx.by_id.get(nid)
        if not n:
            raise Refused(404, "not_found", f"узла {nid!r} нет")
        fields = cx.edge_fields()
        out = []
        for f, spec in fields.items():
            v = n[f]
            for t in (v if isinstance(v, list) else [v]):
                if t in (None, ""):
                    continue
                m = cx.by_id.get(str(t))
                out.append({"field": f, "edge": _str((spec or {}).get("edge")), "id": str(t),
                            "title": _str(m.title) if m else "", "known": bool(m)})
        back = []
        for m in cx.nodes:
            if not m.id or m.id == n.id:
                continue
            for f in fields:
                v = m[f]
                if n.id in (v if isinstance(v, list) else [v]):
                    back.append({"field": f, "id": m.id, "title": _str(m.title), "nexus": _str(m["nexus"])})
        issues = [{"sev": i.sev, "msg": i.msg, "hint": i.hint} for i in c.run_gate(cx) if i.where == n.rel]
        head = {k: v for k, v in n.fm.items() if k != "title"}
        return {**self._card(cx, n), "head": head, "body": n.body, "links": out, "backlinks": back,
                "sources": [_str(s) for s in (n["sources"] or [])], "issues": issues}

    def search(self, q: str) -> dict:
        c = core()
        q = one_line(q)[:200]
        if not q:
            return {"q": "", "hits": []}
        cx = self.cx()
        return {"q": q, "hits": [self._card(cx, n) for _, n in c.Index(cx).search(q, top=25)]}

    def health(self) -> dict:
        return core().health(self.cx())

    def journal(self, days: int = 30) -> dict:
        """История памяти по дням из git: кто, что и зачем менял в GROUND. Нет git — пусто, с пояснением."""
        days = max(1, min(int(days or 30), 365))
        try:
            r = subprocess.run(["git", "-C", str(self.root), "log", f"--since={days} days ago", "--name-status",
                                "--format=%x00%H%x00%aI%x00%an%x00%s", "--", "GROUND"],
                               capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            return {"days": days, "entries": [], "note": "git недоступен"}
        if r.returncode != 0:
            return {"days": days, "entries": [], "note": "vault не в git: журнал строится по истории коммитов"}
        cx = self.cx()
        by_path = {n.rel: n for n in cx.nodes}
        entries, cur = [], None
        for line in r.stdout.split("\n"):
            if line.startswith("\x00"):
                sha, when, who, subject = (line[1:].split("\x00") + ["", "", "", ""])[:4]
                cur = {"sha": sha[:10], "date": when[:10], "time": when[11:16], "author": who, "subject": subject,
                       "files": []}
                entries.append(cur)
            elif line.strip() and cur is not None:
                parts = line.split("\t")
                st, path = parts[0][:1], parts[-1]
                n = by_path.get(path)
                cur["files"].append({"status": st, "path": path, "id": n.id if n else "",
                                     "title": _str(n.title) if n else ""})
        return {"days": days, "entries": entries}

    # ─── очередь ───
    def _scopes(self, cx) -> list[str]:
        zones = ["org"]
        for pid in cx.profiles():
            zones += cx.profile_writes(pid)
        zones += [_str(m.get("scope")) for m in cx.nexuses.values()]
        return [z for z in dict.fromkeys(zones) if z and "<" not in z]

    def _ceiling(self, cx, channel: str, captured_by: str, author: str, authority: str) -> dict:
        ceil = cx.schema["ladder"].get("ceilings") or {}
        channels = ceil.get("channel") or {}
        channel_max = int(channels.get(channel, UNKNOWN_CHANNEL_CP)) if channel else UNKNOWN_CHANNEL_CP
        not_owner = int((ceil.get("authority") or {}).get("not_owner", 2))
        relay = captured_by not in ("", "human") and (not authority or authority.strip() != author.strip())
        cp_max = min(channel_max, not_owner) if relay else channel_max
        why = (f"пересказ {captured_by}: authority {'пуст' if not authority else 'не автор'} — не выше {cp_max}"
               if relay else f"канал {channel or '—'}: не выше {cp_max}"
               + ("" if channel in channels else " (правила канала в лестнице нет)"))
        if cp_max < 9:
            why += f"; выше {cp_max} — только с вашим артефактом-источником"
        return {"cp_default": min(DEFAULT_CP, cp_max), "cp_max": cp_max, "with_artifact": 9, "relay": relay,
                "why": why}

    def _records(self, cx):
        d = cx.ground / "_intake"
        if not d.is_dir():
            return []
        return sorted(p for p in d.rglob("*.md") if p.name not in INTAKE_SKIP)

    def _record(self, cx, p: pathlib.Path) -> dict:
        c = core()
        rel = p.relative_to(self.root).as_posix()
        folder = p.parent.relative_to(cx.ground / "_intake").as_posix()
        item = {"id": record_id(rel), "path": rel, "source": "" if folder == "." else folder}
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as e:
            text, item["error"] = "", f"не читается: {e}"
        m = c.FM_RE.match(text)
        head, statement = {}, text.strip()
        if m:
            try:
                head = c.yaml_parse(m.group(1)) or {}
            except Exception as e:  # noqa: BLE001 — кривая шапка не роняет очередь
                item["error"] = f"шапка не читается — принять нельзя, только отклонить: {e}"
            statement = m.group(2).strip()
        elif "error" not in item:
            item["error"] = "запись без шапки — принять нельзя, только отклонить"
        head = head if isinstance(head, dict) else {}
        s = lambda k: _str(head.get(k)).strip()   # noqa: E731
        day = c.as_date(head.get("date"))
        if not day:
            lead = _LEAD_DATE.match(p.name)
            day = c.as_date(lead.group(1)) if lead else None
        day = day or datetime.date.fromtimestamp(p.stat().st_mtime)
        nexus_hint, type_hint = s("nexus_hint"), s("type_hint")
        hint_ok = nexus_hint in cx.nexuses and (not type_hint or type_hint in cx.node_types(nexus_hint))
        if type_hint and not nexus_hint:
            owners = [k for k in cx.nexuses if type_hint in (cx.nexuses[k].get("node_types") or [])]
            if len(owners) == 1:
                nexus_hint, hint_ok = owners[0], True
        item.update(captured_by=s("captured_by"), date=str(day), age_days=max(0, (self.today() - day).days),
                    title=s("title") or summary(statement)[:120] or p.stem, statement=statement[:BODY_MAX],
                    author=s("author"), authority=s("authority"), channel=s("channel"), link=s("link"),
                    nexus_hint=nexus_hint if hint_ok else "", type_hint=type_hint if hint_ok else "",
                    scope_hint=s("scope_hint"), hash=s("hash") or hash_of(statement),
                    ceiling=self._ceiling(cx, s("channel"), s("captured_by"), s("author"), s("authority")))
        return item

    def queue(self) -> dict:
        cx = self.cx()
        items = sorted((self._record(cx, p) for p in self._records(cx)), key=lambda x: (-x["age_days"], x["path"]))
        drafts = [self._card(cx, n) | {"captured_by": _str(n["captured_by"]),
                                       "sources": [_str(s) for s in (n["sources"] or [])]}
                  for n in cx.nodes if n["status"] == "draft" and n.id]
        inbox = cx.ground / "_intake" / "inbox.md"
        inbox_lines = [x for x in inbox.read_text(encoding="utf-8").splitlines() if _INBOX_LINE.match(x)] \
            if inbox.exists() else []
        rates = cx.schema["profiles"].get("change_rate") or {}
        steps = cx.schema["ladder"].get("steps") or {}
        return {
            "items": items, "count": len(items), "oldest_days": max((x["age_days"] for x in items), default=0),
            "by_source": _counts(x["source"] or "(корень)" for x in items),
            "drafts": drafts, "inbox": inbox_lines[:50],
            "schema": {
                "nexuses": [{"slug": k, "name": _str(v.get("name")) or k, "types": list(v.get("node_types") or []),
                             "scope": _str(v.get("scope")), "owner": _str(v.get("owner"))}
                            for k, v in cx.nexuses.items()],
                "scopes": self._scopes(cx), "change_rates": list(rates),
                "steps": {str(k): _str((v or {}).get("yours") or (v or {}).get("frame")) for k, v in steps.items()},
            },
        }

    def _find(self, cx, rid: str) -> tuple[pathlib.Path, dict]:
        for p in self._records(cx):
            if record_id(p.relative_to(self.root).as_posix()) == rid:
                return p, self._record(cx, p)
        raise Refused(404, "not_found", "записи нет в очереди — её уже разобрали")

    @staticmethod
    def _field(body: dict, key: str, limit: int, default: str = "", required=True) -> str:
        v = body.get(key)
        v = default if v in (None, "") else str(v).strip()
        if required and not v:
            raise Refused(400, "invalid", f"не заполнено поле {key}", key)
        if len(v) > limit or "\n" in v:
            raise Refused(400, "invalid", f"поле {key}: одной строкой до {limit} знаков", key)
        if secret_like(v):
            raise Refused(400, "invalid", f"поле {key} похоже на секрет или ссылку с токеном — уберите", key)
        return v

    def _log_line(self, line: str) -> tuple[pathlib.Path, str | None]:
        """Строка в журнал разбора GROUND/DECIDE/log/<ГГГГ-ММ>.md. Хэш `#…` — чтобы разобранное не вернулось."""
        p = self.root / "GROUND" / "DECIDE" / "log" / f"{self.today():%Y-%m}.md"
        old = p.read_text(encoding="utf-8") if p.exists() else None
        text = old or (f"# Журнал разбора очереди — {self.today():%Y-%m}\n\n"
                       "Строка на каждую запись очереди: принята (→ узел) или отклонена.\n\n"
                       "| Дата | Узел или запись | Решение |\n|---|---|---|\n")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text.rstrip("\n") + "\n" + line + "\n", encoding="utf-8")
        return p, old

    @staticmethod
    def _cell(s) -> str:
        return one_line(s).replace("|", "/")

    def _provenance(self, rec: dict, who: str) -> str:
        return (f"#{rec['hash']} ({self._cell(rec['captured_by'] or '—')}, автор {self._cell(rec['author'] or '—')})"
                + (f", решил {self._cell(who)}" if who else ""))

    def _tool(self, *args) -> subprocess.CompletedProcess:
        env = {k: v for k, v in os.environ.items() if k not in ("CORTEX_PROFILE", "CORTEX_ROOT")}
        return subprocess.run([sys.executable, str(BIN), "--root", str(self.root), *args],
                              capture_output=True, text=True, timeout=60, env=env)

    def accept(self, rid: str, body: dict, who: str = "") -> dict:
        """Запись очереди → узел Нексуса: `cortex node new --by human --status accepted`, провенанс в шапке узла,
        строка в журнал разбора, запись очереди удаляется. Гейт дал ERROR на новом узле — всё откатывается."""
        with self._lock:
            cx = self.cx()
            p, rec = self._find(cx, rid)
            if rec.get("error"):
                raise Refused(400, "invalid", rec["error"])
            nexus = self._field(body, "nexus", 64, rec["nexus_hint"])
            if nexus not in cx.nexuses:
                raise Refused(400, "invalid", f"Нексуса {nexus!r} нет в реестре", "nexus")
            ntype = self._field(body, "type", 64, rec["type_hint"])
            if ntype not in cx.node_types(nexus):
                raise Refused(400, "invalid", f"тип {ntype!r} не объявлен у Нексуса {nexus}: "
                              + ", ".join(sorted(cx.node_types(nexus))), "type")
            title = self._field(body, "title", TITLE_MAX, rec["title"])
            nid = self._field(body, "id", 64, required=False)
            if nid and not NODE_ID.match(nid):
                raise Refused(400, "invalid", "id — латиница в нижнем регистре, цифры и дефис, до 64", "id")
            scopes = self._scopes(cx)
            scope = self._field(body, "scope", 64,
                                rec["scope_hint"] if rec["scope_hint"] in scopes else _str(cx.nexuses[nexus].get("scope"))
                                or "org")
            if scope not in scopes:
                raise Refused(400, "invalid", f"зона — {' | '.join(scopes)}", "scope")
            rates = list(cx.schema["profiles"].get("change_rate") or {}) or ["unknown"]
            change_rate = self._field(body, "change_rate", 16, "high" if "high" in rates else rates[0])
            if change_rate not in rates:
                raise Refused(400, "invalid", f"change_rate — {' | '.join(rates)}", "change_rate")
            owner = self._field(body, "owner", FIELD_MAX, _str(cx.nexuses[nexus].get("owner")) or "Product Engineer")
            given = body.get("sources") or []
            if isinstance(given, str):
                given = [x for x in re.split(r"[\n,]", given)]
            if not isinstance(given, list):
                raise Refused(400, "invalid", "sources — список", "sources")
            given = [one_line(s) for s in given if one_line(s)]
            if any(len(s) > SOURCE_MAX for s in given) or secret_like(*given):
                raise Refused(400, "invalid", f"источник — одной строкой до {SOURCE_MAX} знаков, без секретов", "sources")
            auto = [s for s in (rec["link"], f"intake:{rec['path']}#{rec['hash']}") if s]
            extra = [s for s in given if s not in auto]
            sources = list(dict.fromkeys(auto + given))
            ceil = rec["ceiling"]
            cp_max = ceil["with_artifact"] if extra else ceil["cp_max"]
            try:
                cp = int(body.get("cp", ceil["cp_default"]))
            except (TypeError, ValueError):
                cp = -1
            if not 2 <= cp <= 9:
                raise Refused(400, "invalid", "CP — ступень от 2 до 9 (SCHEMA/ladder.yaml)", "cp")
            if cp > cp_max:
                raise Refused(422, "ceiling", f"CP {cp} выше потолка {cp_max}: {ceil['why']}. Добавьте в источники "
                              "свой артефакт (документ, тикет, письмо — не ссылку записи) или понизьте CP", "cp")
            text = str(body.get("body") or "").strip()
            if len(text) > BODY_MAX or re.search(r"^---", text, re.M):
                raise Refused(400, "invalid", f"текст узла — до {BODY_MAX} знаков, без строки ---", "body")
            if secret_like(text, rec["statement"], rec["link"]):
                raise Refused(400, "invalid", "текст похож на секрет или ссылку с токеном — уберите или отклоните запись",
                              "body")
            text = text or (rec["statement"] + (f"\n\nИсточник: {rec['link']} ({rec['author'] or '—'})."
                                                if rec["link"] else ""))
            args = ["node", "new", f"--nexus={nexus}", f"--type={ntype}", f"--title={title}", f"--scope={scope}",
                    f"--cp={cp}", f"--change-rate={change_rate}", f"--owner={owner}", "--by=human",
                    "--status=accepted", f"--body={text}", *[f"--source={s}" for s in sources]]
            if nid:
                args.append(f"--id={nid}")
            if body.get("force") is True:
                args.append("--force")
            r = self._tool(*args)
            out = _ANSI.sub("", (r.stdout or "") + (r.stderr or ""))
            m = re.search(r"узел создан:\s*(\S+)", out)
            if r.returncode != 0 or not m:
                why = out.strip().lstrip("✗ ").strip()
                code = "duplicate" if "дубликат" in why else "exists" if "уже есть" in why else "cortex"
                raise Refused(422, code, "cortex не создал узел: " + why[-500:], "title" if code != "cortex" else "")
            node_path = self.root / m.group(1)
            record_text = p.read_text(encoding="utf-8")
            try:
                c = core()
                node_text = node_path.read_text(encoding="utf-8")
                end = node_text.find("\n---", 3)
                have = set(re.findall(r"^([A-Za-z_][\w-]*):", node_text[:end], re.M))
                prov = {"channel": rec["channel"], "author": rec["author"], "authority": rec["authority"],
                        "link": rec["link"], "intake_by": rec["captured_by"]}
                add = c.yaml_dump({k: v for k, v in prov.items() if v and k not in have})
                if add:
                    node_text = node_text[:end] + "\n" + add + node_text[end:]
                    node_path.write_text(node_text, encoding="utf-8")
                cx2 = self.cx()
                rel = node_path.relative_to(self.root).as_posix()
                bad = [i for i in core().run_gate(cx2) if i.where == rel and i.sev == "ERROR"]
                if bad:
                    raise Refused(422, "gate", "гейт отклонил узел: " + "; ".join(i.msg for i in bad[:3]))
                log_p, log_old = self._log_line(
                    f"| {self.today()} | {node_path.stem} | принято из intake:{rec['path']} {self._provenance(rec, who)} |")
                p.unlink()
            except Exception:
                node_path.unlink(missing_ok=True)
                if not p.exists():
                    p.write_text(record_text, encoding="utf-8")
                raise
            sha = self._commit([node_path, log_p, p], f"Знание принято: {title[:80]} ← {rec['path']}", who)
            return {"ok": True, "node": node_path.stem, "path": rel, "commit": sha}

    def reject(self, rid: str, body: dict, who: str = "") -> dict:
        with self._lock:
            cx = self.cx()
            p, rec = self._find(cx, rid)
            reason = self._field(body, "reason", REASON_MAX, required=False)
            log_p, _ = self._log_line(f"| {self.today()} | intake:{rec['path']} | отклонено: "
                                      f"{self._cell(reason) or 'без причины'} {self._provenance(rec, who)} |")
            p.unlink()
            sha = self._commit([log_p, p], f"Знание отклонено: {rec['path']}", who)
            return {"ok": True, "commit": sha}

    def draft(self, nid: str, action: str, who: str = "") -> dict:
        """Черновик агента → accepted или rejected через `cortex review`."""
        if action not in ("accept", "reject"):
            raise Refused(404, "not_found", "действие — accept или reject")
        with self._lock:
            cx = self.cx()
            n = cx.by_id.get(nid)
            if not n or n["status"] != "draft":
                raise Refused(404, "not_found", f"черновика {nid!r} нет — его уже разобрали")
            r = self._tool("review", f"--{action}", nid)
            if r.returncode != 0:
                raise Refused(422, "cortex", _ANSI.sub("", r.stderr or r.stdout or "").strip()[-500:])
            word = "принят" if action == "accept" else "отклонён"
            sha = self._commit([n.path], f"Черновик {word}: {_str(n.title)[:80]}", who)
            return {"ok": True, "node": nid, "status": "accepted" if action == "accept" else "rejected", "commit": sha}

    # ─── git ───
    def _commit(self, paths, message: str, who: str = "") -> str:
        """Коммит ровно затронутых путей — не `git add -A`: чужой файл в рабочей копии не уедет в память молча."""
        if not self.commit_enabled:
            return ""
        rels = [pathlib.Path(x).resolve().relative_to(self.root).as_posix() for x in paths]

        def git(*a):
            return subprocess.run(["git", "-C", str(self.root), *a], capture_output=True, text=True, timeout=30)

        known = [r for r in rels if (self.root / r).exists()
                 or git("ls-files", "--error-unmatch", "--", r).returncode == 0]
        if not known:
            return ""
        git("add", "-A", "--", *known)
        ident = ["-c", "user.name=" + (who or "cortex-studio"), "-c", "user.email=studio@cortex.local"] \
            if git("config", "user.email").returncode != 0 else []
        msg = message + (f"\n\nРешил: {who}" if who else "")
        r = subprocess.run(["git", "-C", str(self.root), *ident, "commit", "-q", "-m", msg, "--", *known],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            return ""
        return git("rev-parse", "--short", "HEAD").stdout.strip()


def _counts(values) -> dict:
    out: dict[str, int] = {}
    for v in values:
        out[v] = out.get(v, 0) + 1
    return out
