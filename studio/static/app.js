// Студия Кортекса — страница памяти организации. Без библиотек: DOM строится узлами, текст не вставляется как HTML.
"use strict";

const API = new URL("api/", document.baseURI.replace(/[#?].*$/, "").replace(/[^/]*$/, ""));
const main = document.getElementById("main");
let me = { can_write: false };
let overview = null;

// ─── утилиты ───
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid === null || kid === undefined || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}
const nodeHref = (id) => "#/node/" + encodeURIComponent(id);
const plural = (n, one, few, many) => {
  const m10 = n % 10, m100 = n % 100;
  return m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20) ? few : many;
};
function toast(text) {
  const t = document.getElementById("toast");
  t.textContent = text; t.hidden = false;
  clearTimeout(toast.timer); toast.timer = setTimeout(() => { t.hidden = true; }, 4200);
}
async function api(path, opts) {
  const res = await fetch(new URL(path, API), {
    credentials: "same-origin",
    ...(opts && opts.body ? { method: "POST", headers: { "Content-Type": "application/json", "X-Cortex-Studio": "1" },
                              body: JSON.stringify(opts.body) } : {}),
  });
  let data = {};
  try { data = await res.json(); } catch (_) { /* не JSON — ниже ошибка */ }
  if (!res.ok) { const e = new Error(data.message || ("HTTP " + res.status)); e.field = data.field; e.code = data.error; throw e; }
  return data;
}
function ripeBadge(r) {
  const map = { fresh: ["свежий", "ok"], ripening: ["созревает", "warn"], wilting: ["протух", "crit"] };
  const [t, c] = map[r] || [r || "свежесть —", ""];
  return h("span", { class: "pill " + c }, t);
}
function cpBadge(n) {
  if (n.cp === null || n.cp === undefined || n.cp === "") return null;
  const eff = n.effective_cp !== undefined && n.effective_cp !== null && n.effective_cp !== n.cp ? " → " + n.effective_cp : "";
  return h("span", { class: "pill accent", title: "ступень уверенности (CP) с учётом распада" }, "CP " + n.cp + eff);
}

// ─── мини-markdown: заголовки, списки, цитаты, таблицы, код, **жирный**, `код`, [ссылки](…), [[узел]] ───
function inline(text) {
  const out = [];
  const re = /(`[^`]+`)|(\*\*[^*]+\*\*)|(\[\[([A-Za-z0-9._-]{1,80})(?:\|([^\]]*))?\]\])|(\[([^\]]+)\]\(([^)\s]+)\))/g;
  let last = 0, m;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index));
    if (m[1]) out.push(h("code", {}, m[1].slice(1, -1)));
    else if (m[2]) out.push(h("b", {}, m[2].slice(2, -2)));
    else if (m[3]) out.push(h("a", { href: nodeHref(m[4]) }, m[5] || m[4]));
    else if (m[6]) {
      const url = m[8];
      const safe = /^(https?:|mailto:)/i.test(url);
      out.push(safe ? h("a", { href: url, target: "_blank", rel: "noopener noreferrer" }, m[7]) : h("span", {}, m[7]));
    }
    last = re.lastIndex;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}
function markdown(src) {
  const root = h("div", { class: "prose" });
  const lines = String(src || "").replace(/\r\n/g, "\n").split("\n");
  let i = 0, list = null, para = [];
  const flush = () => {
    if (para.length) { root.append(h("p", {}, inline(para.join(" ")))); para = []; }
    list = null;
  };
  while (i < lines.length) {
    const line = lines[i];
    const t = line.trim();
    if (t.startsWith("```")) {
      flush();
      const code = [];
      for (i++; i < lines.length && !lines[i].trim().startsWith("```"); i++) code.push(lines[i]);
      root.append(h("pre", {}, h("code", {}, code.join("\n"))));
      i++; continue;
    }
    if (t.startsWith("<!--")) { while (i < lines.length && !lines[i].includes("-->")) i++; i++; continue; }
    if (!t) { flush(); i++; continue; }
    let m = t.match(/^(#{1,4})\s+(.*)$/);
    if (m) { flush(); root.append(h("h" + Math.min(4, m[1].length + 1), {}, inline(m[2]))); i++; continue; }
    if (t.startsWith("|")) {
      flush();
      const rows = [];
      for (; i < lines.length && lines[i].trim().startsWith("|"); i++) rows.push(lines[i].trim());
      const cells = (r) => r.replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
      const body = rows.filter((r) => !/^\|[\s:|-]+\|$/.test(r));
      const table = h("table", {});
      body.forEach((r, k) => table.append(h("tr", {}, cells(r).map((c) => h(k === 0 && rows.length > 1 ? "th" : "td", {}, inline(c))))));
      root.append(table); continue;
    }
    if (t.startsWith(">")) { flush(); root.append(h("blockquote", {}, inline(t.replace(/^>\s?/, "")))); i++; continue; }
    m = t.match(/^([-*]|\d+[.)])(?:\s+(.*))?$/);
    if (m && !m[2]) { i++; continue; }   // пустой пункт шаблона «- » не рисуем
    if (m) {
      if (para.length) { root.append(h("p", {}, inline(para.join(" ")))); para = []; }
      if (!list) { list = h(/\d/.test(m[1]) ? "ol" : "ul", {}); root.append(list); }
      list.append(h("li", {}, inline(m[2]))); i++; continue;
    }
    list = null; para.push(t); i++;
  }
  flush();
  return root;
}

// ─── каркас ───
function setTab(tab) {
  document.querySelectorAll(".tabs a").forEach((a) => a.classList.toggle("on", a.dataset.tab === tab));
}
function view(...kids) { main.replaceChildren(h("div", {}, kids)); main.focus({ preventScroll: true }); window.scrollTo(0, 0); }
function failed(e) { view(h("div", { class: "alert crit" }, "Не загрузилось: " + e.message)); }

async function loadShell() {
  try { me = await api("me"); } catch (_) { me = { can_write: false }; }
  try { overview = await api("overview"); } catch (e) { overview = null; return failed(e); }
  const org = overview.org;
  document.getElementById("org").textContent = org.configured ? [org.company, org.product].filter(Boolean).join(" · ") : "память организации";
  document.title = org.configured && org.company ? "Кортекс — " + org.company : "Студия Кортекса";
  const toc = document.getElementById("toc");
  toc.replaceChildren(
    ...overview.chapters.map((c) => h("a", { href: "#/chapter/" + c.slug, "data-slug": c.slug }, h("span", {}, c.name),
      h("span", { class: "n" }, c.nodes || ""))),
    h("a", { href: "#/chapter/decide", "data-slug": "decide" }, h("span", {}, "Решения и ставки"),
      h("span", { class: "n" }, overview.decide.nodes || "")));
  const waiting = overview.health.intake.count + overview.health.drafts.count;
  const att = document.getElementById("attention");
  att.hidden = !waiting;
  document.getElementById("attention-n").textContent = waiting;
  const qc = document.getElementById("queue-count");
  qc.hidden = !waiting; qc.textContent = waiting;
  qc.className = "pill " + (overview.health.status === "crit" ? "crit" : "warn");
}
function markToc(slug) {
  document.querySelectorAll("#toc a").forEach((a) => a.classList.toggle("on", a.dataset.slug === slug));
}

// ─── Книга ───
function alertsBlock(health) {
  const items = (health.alerts || []).map((a) => h("div", { class: "alert " + a.level },
    a.what === "intake" || a.what === "drafts" ? h("a", { href: "#/queue" }, a.text) : a.text));
  return items.length ? h("div", { class: "alerts" }, items) : null;
}
async function showBook() {
  setTab("book"); markToc("");
  if (!overview) await loadShell();
  if (!overview) return;
  const o = overview;
  const filled = o.chapters.filter((c) => c.nodes > 0).length;
  view(
    h("div", { class: "eyebrow" }, "Фундаментальный кортекс"),
    h("h1", {}, "Память организации"),
    h("p", { class: "lead" }, o.org.configured && o.org.idea ? o.org.idea + " " : "",
      `На чём стоит работа: продукт, потребители, операционная модель, люди, цели и решения. ${o.totals.nodes} ` +
      `${plural(o.totals.nodes, "узел", "узла", "узлов")} в ${o.chapters.length} ${plural(o.chapters.length, "главе", "главах", "главах")}, ` +
      `наполнено ${filled}.`),
    !o.org.configured ? h("div", { class: "alert warn" }, "Кортекс ещё не настроен: ", h("code", {}, "bin/cortex doctor"),
      " покажет план, а ИИ-агент проведёт по ", h("code", {}, "ONBOARDING.md"), ".") : null,
    alertsBlock(o.health),
    h("div", { class: "grid" },
      o.chapters.map((c) => h("a", { class: "card", href: "#/chapter/" + c.slug },
        h("h3", {}, c.name),
        h("div", { class: "num" + (c.nodes ? "" : " zero") }, c.nodes),
        h("div", { class: "muted small" }, plural(c.nodes, "узел", "узла", "узлов"),
          c.onboarded ? " · онбординг: " + c.onboarded : "", c.drafts ? ` · черновиков ${c.drafts}` : "",
          c.wilting ? ` · протухло ${c.wilting}` : ""),
        h("p", {}, c.purpose))),
      h("a", { class: "card", href: "#/chapter/decide" }, h("h3", {}, "Решения и ставки"),
        h("div", { class: "num" + (o.decide.nodes ? "" : " zero") }, o.decide.nodes),
        h("div", { class: "muted small" }, plural(o.decide.nodes, "узел", "узла", "узлов")),
        h("p", {}, "принятые решения, ставки и доказательства — почему мы делаем так"))),
    o.recent.length ? [h("h2", {}, "Недавно обновлённое"), h("div", { class: "list" }, o.recent.map(nodeRow))] : null,
    o.stale.length ? [h("h2", {}, "Протухло — верифицировать или понизить CP"), h("div", { class: "list" }, o.stale.map(nodeRow))] : null,
  );
}
function nodeRow(n) {
  return h("a", { class: "row", href: nodeHref(n.id) },
    h("div", { class: "t" }, n.title),
    n.summary ? h("div", { class: "s" }, n.summary) : null,
    h("div", { class: "meta" }, n.type ? h("span", {}, n.type) : null, cpBadge(n), ripeBadge(n.ripeness),
      n.status === "draft" ? h("span", { class: "pill warn" }, "черновик") : null,
      n.owner ? h("span", {}, n.owner) : null, n.updated ? h("span", {}, n.updated) : null));
}
async function showChapter(slug) {
  setTab("book"); markToc(slug);
  let c;
  try { c = await api("chapter?slug=" + encodeURIComponent(slug)); } catch (e) { return failed(e); }
  view(
    h("div", { class: "eyebrow" }, h("a", { href: "#/" }, "Книга"), " / глава"),
    h("h1", {}, c.name),
    h("p", { class: "lead" }, c.purpose, c.owner ? " · владелец: " + c.owner : "", c.onboarded ? " · онбординг: " + c.onboarded : ""),
    c.intro ? markdown(c.intro) : null,
    h("h2", {}, "Узлы главы ", h("span", { class: "pill" }, c.nodes.length)),
    c.nodes.length ? h("div", { class: "list" }, c.nodes.map(nodeRow))
      : h("div", { class: "empty" }, "Глава пуста. Знание сюда попадает из очереди: агенты и люди кладут кандидатов в ",
          h("code", {}, "GROUND/_intake/"), ", а вы принимаете их в разделе ", h("a", { href: "#/queue" }, "«Разбор»"), "."),
    c.types && c.types.length ? h("p", { class: "muted small" }, "Типы узлов: " + c.types.join(", ")) : null);
}
async function showNode(id) {
  setTab("book");
  let n;
  try { n = await api("node?id=" + encodeURIComponent(id)); } catch (e) { return failed(e); }
  markToc(n.layer === "decisions" ? "decide" : n.nexus);
  const head = Object.entries(n.head).filter(([k]) => !["body"].includes(k));
  view(
    h("div", { class: "eyebrow" }, h("a", { href: "#/" }, "Книга"), " / ",
      n.layer === "decisions" ? h("a", { href: "#/chapter/decide" }, "решения") : h("a", { href: "#/chapter/" + n.nexus }, n.nexus || "узел")),
    h("h1", {}, n.title),
    h("div", { class: "badges" }, cpBadge(n), ripeBadge(n.ripeness), n.status ? h("span", { class: "pill" }, n.status) : null,
      n.type ? h("span", { class: "pill" }, n.type) : null, n.scope ? h("span", { class: "pill" }, "зона " + n.scope) : null),
    n.issues.length ? h("div", { class: "alerts" }, n.issues.map((i) => h("div", { class: "alert " + (i.sev === "ERROR" ? "crit" : "warn") },
      i.msg, i.hint ? h("div", { class: "small" }, "→ " + i.hint) : null))) : null,
    h("h3", {}, "На чём держится"),
    n.sources.length ? h("ul", {}, n.sources.map((s) => h("li", {}, /^https?:/i.test(s) ? h("a", { href: s, target: "_blank", rel: "noopener noreferrer" }, s) : s)))
      : h("p", { class: "alert crit" }, "Нет источника — узел не должен существовать"),
    markdown(n.body),
    n.links.length ? [h("h3", {}, "Связи"), h("div", { class: "list" }, n.links.map((l) => l.known
      ? h("a", { class: "row", href: nodeHref(l.id) }, h("span", { class: "muted small" }, l.field + " → "), l.title || l.id)
      : h("div", { class: "row" }, h("span", { class: "muted small" }, l.field + " → "), l.id)))] : null,
    n.backlinks.length ? [h("h3", {}, "На него ссылаются"), h("div", { class: "list" }, n.backlinks.map((l) =>
      h("a", { class: "row", href: nodeHref(l.id) }, h("span", { class: "muted small" }, l.field + " ← "), l.title || l.id)))] : null,
    h("h3", {}, "Шапка"),
    h("dl", { class: "kv" }, head.map(([k, v]) => [h("dt", {}, k), h("dd", {}, Array.isArray(v) ? v.join(", ") : typeof v === "object" && v ? JSON.stringify(v) : String(v))])),
    h("p", { class: "muted small" }, h("code", {}, n.path)));
}
async function showSearch(q) {
  setTab("book"); markToc("");
  document.getElementById("q").value = q;
  let r;
  try { r = await api("search?q=" + encodeURIComponent(q)); } catch (e) { return failed(e); }
  view(h("div", { class: "eyebrow" }, "Поиск"), h("h1", {}, "«" + q + "»"),
    r.hits.length ? h("div", { class: "list" }, r.hits.map(nodeRow))
      : h("div", { class: "empty" }, "Память об этом не знает. «Не знаю» — честный ответ: добавьте знание через очередь."));
}

// ─── Разбор ───
let queueFilter = "";
async function showQueue() {
  setTab("queue"); markToc("");
  let q;
  try { q = await api("queue"); } catch (e) { return failed(e); }
  const sources = Object.entries(q.by_source);
  const items = q.items.filter((x) => !queueFilter || (x.source || "(корень)") === queueFilter);
  view(
    h("div", { class: "eyebrow" }, "Разбор"),
    h("h1", {}, "Что ждёт решения"),
    h("p", { class: "lead" }, "Агенты, боты и люди кладут кандидатов в очередь. Знанием запись становится только после вашего «Принять»: ",
      "узел получает источник и честную ступень уверенности, решение пишется в журнал разбора, отклонённое не вернётся."),
    !me.can_write ? h("div", { class: "alert warn" }, "Только просмотр: ", me.why || "запись выключена") : null,
    h("h2", {}, "Очередь ", h("span", { class: "pill " + (q.oldest_days > 7 ? "crit" : q.oldest_days > 3 ? "warn" : "") }, q.count),
      q.count ? h("span", { class: "muted small" }, ` · самой старой ${q.oldest_days} дн.`) : null),
    sources.length > 1 ? h("div", { class: "filters" },
      h("button", { class: queueFilter ? "" : "on", onclick: () => { queueFilter = ""; showQueue(); } }, "все " + q.count),
      sources.map(([s, n]) => h("button", { class: queueFilter === s ? "on" : "", onclick: () => { queueFilter = s; showQueue(); } }, `${s} ${n}`))) : null,
    items.length ? h("div", { class: "list" }, items.map((x) => recordCard(x, q.schema)))
      : h("div", { class: "empty" }, "Очередь пуста."),
    h("h2", {}, "Черновики агентов ", h("span", { class: "pill" }, q.drafts.length)),
    h("p", { class: "muted small" }, "Узлы, записанные агентом через ", h("code", {}, "cortex node new"), ": как факт не участвуют, пока вы не приняли."),
    q.drafts.length ? h("div", { class: "list" }, q.drafts.map(draftCard)) : h("div", { class: "empty" }, "Черновиков нет."),
    q.inbox.length ? [h("h2", {}, "Быстрые вставки inbox.md ", h("span", { class: "pill" }, q.inbox.length)),
      h("p", { class: "muted small" }, "Строки разбираются агентом по навыку cortex-intake или вручную."),
      h("pre", {}, q.inbox.join("\n"))] : null);
}
function recordCard(x, schema) {
  const box = h("div", { class: "rec" });
  const busy = (on) => box.querySelectorAll("button").forEach((b) => { b.disabled = on; });
  const reject = async () => {
    const reason = prompt("Почему отклоняем? (необязательно)", "");
    if (reason === null) return;
    busy(true);
    try { await api(`queue/${x.id}/reject`, { body: { reason } }); toast("Отклонено"); box.remove(); refreshCounts(); }
    catch (e) { toast(e.message); busy(false); }
  };
  const open = () => { if (!box.querySelector(".form")) box.append(acceptForm(x, schema, box)); };
  box.append(
    h("div", { class: "t" }, x.title),
    h("div", { class: "st" }, x.statement),
    h("div", { class: "meta" },
      h("span", {}, x.source || "(корень)"), h("span", {}, x.date + (x.age_days ? ` · ${x.age_days} дн.` : "")),
      x.author ? h("span", {}, "автор: " + x.author) : null, x.channel ? h("span", {}, "канал: " + x.channel) : null,
      x.link ? (/^https?:/i.test(x.link) ? h("a", { href: x.link, target: "_blank", rel: "noopener noreferrer" }, x.link) : h("span", {}, x.link)) : null,
      x.nexus_hint ? h("span", { class: "pill" }, x.nexus_hint + (x.type_hint ? " / " + x.type_hint : "")) : null),
    x.error ? h("div", { class: "alert crit" }, x.error) : h("div", { class: "ceil" }, "Потолок: " + x.ceiling.why),
    me.can_write ? h("div", { class: "actions" },
      x.error ? null : h("button", { class: "btn primary", type: "button", onclick: open }, "Принять…"),
      h("button", { class: "btn", type: "button", onclick: reject }, "Отклонить")) : null);
  return box;
}
function acceptForm(x, schema, box) {
  const nexuses = schema.nexuses;
  const sel = (name, opts, value) => h("select", { name }, opts.map((o) => h("option", { value: o, selected: o === value ? true : null }, o)));
  const startNexus = x.nexus_hint || "";
  const nexus = h("select", { name: "nexus" }, h("option", { value: "" }, "— выберите —"),
    nexuses.map((n) => h("option", { value: n.slug, selected: n.slug === startNexus ? true : null }, n.name)));
  const type = h("select", { name: "type" });
  const fillTypes = () => {
    const n = nexuses.find((v) => v.slug === nexus.value);
    type.replaceChildren(...(n ? n.types : []).map((t) => h("option", { value: t, selected: t === x.type_hint ? true : null }, t)));
  };
  nexus.addEventListener("change", fillTypes); fillTypes();
  const cp = h("select", { name: "cp" });
  const sources = h("textarea", { name: "sources", rows: 2, placeholder: "ваш артефакт: документ, тикет, письмо — по строке" });
  const fillCp = () => {
    const max = sources.value.trim() ? x.ceiling.with_artifact : x.ceiling.cp_max;
    const cur = Number(cp.value) || x.ceiling.cp_default;
    cp.replaceChildren(...[2, 3, 4, 5, 6, 7, 8, 9].filter((v) => v <= max).map((v) =>
      h("option", { value: v, selected: v === Math.min(cur, max) ? true : null }, `${v} — ${schema.steps[v] || ""}`)));
  };
  sources.addEventListener("input", fillCp); fillCp();
  const err = h("div", { class: "err" });
  const form = h("form", { class: "form" },
    h("label", { class: "wide" }, "Заголовок узла", h("input", { name: "title", value: x.title, maxlength: 200, required: true })),
    h("label", {}, "Глава (Нексус)", nexus), h("label", {}, "Тип узла", type),
    h("label", {}, "Зона", sel("scope", schema.scopes, x.scope_hint && schema.scopes.includes(x.scope_hint) ? x.scope_hint : "org")),
    h("label", {}, "Как быстро меняется", sel("change_rate", schema.change_rates, schema.change_rates.includes("high") ? "high" : schema.change_rates[0])),
    h("label", {}, "Ступень уверенности (CP)", cp),
    h("label", {}, "Владелец знания", h("input", { name: "owner", placeholder: "по умолчанию — владелец главы", maxlength: 120 })),
    h("label", { class: "wide" }, "Свой источник (поднимает потолок CP)", sources),
    h("label", { class: "wide" }, "Текст узла (пусто — утверждение записи и её источник)", h("textarea", { name: "body", rows: 4, placeholder: x.statement.slice(0, 200) })),
    err,
    h("div", { class: "actions wide" },
      h("button", { class: "btn primary", type: "submit" }, "Принять в память"),
      h("button", { class: "btn", type: "button", onclick: () => form.remove() }, "Отмена")));
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    err.textContent = "";
    const f = new FormData(form);
    const body = Object.fromEntries([...f.entries()].filter(([, v]) => String(v).trim() !== ""));
    if (body.sources) body.sources = String(body.sources).split("\n").map((s) => s.trim()).filter(Boolean);
    body.cp = Number(body.cp);
    form.querySelectorAll("button").forEach((b) => { b.disabled = true; });
    try {
      const r = await api(`queue/${x.id}/accept`, { body });
      toast("Принято: " + r.node + (r.commit ? " · коммит " + r.commit : ""));
      box.replaceChildren(h("div", {}, "✓ Принято → ", h("a", { href: nodeHref(r.node) }, body.title || r.node)));
      refreshCounts();
    } catch (e) {
      err.textContent = e.message;
      if (e.code === "duplicate") {
        err.append(" ", h("button", { class: "btn", type: "button", onclick: async () => {
          body.force = true;
          try { const r = await api(`queue/${x.id}/accept`, { body }); toast("Принято: " + r.node); box.remove(); refreshCounts(); }
          catch (e2) { err.textContent = e2.message; }
        } }, "Это другой объект — принять"));
      }
      form.querySelectorAll("button").forEach((b) => { b.disabled = false; });
    }
  });
  return form;
}
function draftCard(n) {
  const box = h("div", { class: "rec" });
  const act = async (action) => {
    box.querySelectorAll("button").forEach((b) => { b.disabled = true; });
    try { await api(`drafts/${encodeURIComponent(n.id)}/${action}`, { body: {} }); toast(action === "accept" ? "Принят" : "Отклонён"); box.remove(); refreshCounts(); }
    catch (e) { toast(e.message); box.querySelectorAll("button").forEach((b) => { b.disabled = false; }); }
  };
  box.append(h("div", { class: "t" }, h("a", { href: nodeHref(n.id) }, n.title)),
    n.summary ? h("div", { class: "st" }, n.summary) : null,
    h("div", { class: "meta" }, h("span", {}, n.nexus + " / " + n.type), cpBadge(n), h("span", {}, "записал: " + (n.captured_by || "—")),
      n.sources.length ? h("span", {}, "источник: " + n.sources.slice(0, 2).join(", ")) : h("span", { class: "pill crit" }, "без источника")),
    me.can_write ? h("div", { class: "actions" },
      h("button", { class: "btn primary", type: "button", onclick: () => act("accept") }, "Принять"),
      h("button", { class: "btn", type: "button", onclick: () => act("reject") }, "Отклонить")) : null);
  return box;
}
async function refreshCounts() { overview = null; await loadShell(); }

// ─── Журнал ───
async function showJournal() {
  setTab("journal"); markToc("");
  let j;
  try { j = await api("journal?days=30"); } catch (e) { return failed(e); }
  const days = {};
  j.entries.forEach((e) => { (days[e.date] = days[e.date] || []).push(e); });
  const label = { A: "добавлен", M: "изменён", D: "удалён", R: "переименован" };
  view(h("div", { class: "eyebrow" }, "Журнал"), h("h1", {}, "Как менялась память"),
    h("p", { class: "lead" }, "Кто, что и зачем менял в GROUND за 30 дней — по истории git."),
    j.note ? h("div", { class: "alert warn" }, j.note) : null,
    !j.entries.length && !j.note ? h("div", { class: "empty" }, "За 30 дней изменений нет.") : null,
    Object.entries(days).map(([d, es]) => [h("div", { class: "day" }, d), h("div", { class: "list" }, es.map((e) =>
      h("div", { class: "row commit" }, h("div", { class: "t" }, e.subject),
        h("div", { class: "meta" }, h("span", {}, e.time), h("span", {}, e.author), h("code", {}, e.sha)),
        h("ul", { class: "files" }, e.files.slice(0, 12).map((f) => h("li", {}, (label[f.status] || f.status) + ": ",
          f.id && f.status !== "D" ? h("a", { href: nodeHref(f.id) }, f.title || f.id) : f.path)),
          e.files.length > 12 ? h("li", {}, `… ещё ${e.files.length - 12}`) : null))))]));
}

// ─── Здоровье ───
async function showHealth() {
  setTab("health"); markToc("");
  let x;
  try { x = await api("health"); } catch (e) { return failed(e); }
  const tile = (title, value, note, level) => h("div", { class: "card" }, h("h3", {}, title),
    h("div", { class: "num" + (level ? "" : "") }, value), note ? h("p", {}, note) : null);
  view(h("div", { class: "eyebrow" }, "Здоровье"), h("h1", {}, "Можно ли верить памяти"),
    h("p", { class: "lead" }, "То же, что ", h("code", {}, "bin/cortex health"), ": гейт, очередь, черновики, протухшее, конфликты, срезы профилей."),
    h("div", { class: "alerts" }, x.alerts.length ? x.alerts.map((a) => h("div", { class: "alert " + a.level }, a.text))
      : h("div", { class: "alert ok" }, "Всё в норме")),
    h("div", { class: "grid" },
      tile("Гейт", x.gate.errors ? `${x.gate.errors} ошибок` : "зелёный", `предупреждений ${x.gate.warnings}`),
      tile("Очередь", x.intake.count, x.intake.oldest_days !== null ? `самой старой ${x.intake.oldest_days} дн.` : "пусто"),
      tile("Черновики", x.drafts.count, "ждут приёмки"),
      tile("Протухло", x.wilting.count, `из ${x.wilting.nodes} узлов`),
      tile("Конфликты", x.conflicts, "расхождения между зонами"),
      tile("Сироты", x.orphans === null ? "—" : x.orphans, "знание, не служащее цели")),
    Object.keys(x.packs || {}).length ? [h("h2", {}, "Срезы профилей"), h("div", { class: "list" },
      Object.entries(x.packs).map(([p, v]) => h("div", { class: "row" }, h("span", { class: "t" }, p), " ",
        h("span", { class: "pill " + (v.current ? "ok" : "warn") }, v.current ? "актуален" : "отстал"),
        h("span", { class: "muted small" }, ` ${v.chars} знаков`))))] : null,
    h("p", { class: "muted small" }, `Кортекс ${x.version} · ${x.date}`));
}

// ─── маршруты ───
function route() {
  const hash = decodeURIComponent(location.hash.replace(/^#\/?/, ""));
  const [head, ...rest] = hash.split("/");
  const arg = rest.join("/");
  if (head === "chapter" && arg) return showChapter(arg);
  if (head === "node" && arg) return showNode(arg);
  if (head === "search") return showSearch(arg);
  if (head === "queue") return showQueue();
  if (head === "journal") return showJournal();
  if (head === "health") return showHealth();
  return showBook();
}
document.getElementById("search").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const q = document.getElementById("q").value.trim();
  if (q) location.hash = "#/search/" + encodeURIComponent(q);
});
(function theme() {
  const btn = document.getElementById("theme");
  let saved = null;
  try { saved = localStorage.getItem("cortex-theme"); } catch (_) { /* приватный режим */ }
  if (saved) document.documentElement.dataset.theme = saved;
  btn.addEventListener("click", () => {
    const dark = document.documentElement.dataset.theme
      ? document.documentElement.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    const next = dark ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("cortex-theme", next); } catch (_) { /* без памяти темы */ }
  });
})();
window.addEventListener("hashchange", route);
loadShell().then(route);
