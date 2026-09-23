#!/usr/bin/env bash
# Сравнение «до Кортекса» и «после»: один и тот же набор фактов, заданы одни и
# те же шесть вопросов PO — сначала папке заметок, потом Кортексу.
#
# Три теста этого репозитория отвечают на разные вопросы:
#   tests/smoke.sh        команды не падают
#   tests/acceptance.sh   гарантии держатся (отказы, распад, слабое звено)
#   tests/comparison.sh   разницу видно человеку — и она измерима
#
# Стенд «до» — не соломенное чучело: те же факты там есть, и поиск их находит.
# Разница не в том, что знания нет, а в том, что оно **не считается**: у текста
# нет ступени, срока годности, владельца и потолка, поэтому ответ на вопрос
# «успеем ли» собирается заново каждый раз и каждый раз по-новому.
#
# Тест фальсифицируем с обеих сторон. Если у заметок появятся поля — стенд «до»
# перестанет быть «до», и тест покраснеет. Если Кортекс перестанет считать —
# покраснеет вторая половина. Зелёный здесь означает, что разница ещё есть.
#
#   tests/comparison.sh          собрать оба стенда и прогнать сравнение
#   tests/comparison.sh --keep   оставить стенды, чтобы посмотреть файлы
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cortex-comparison.XXXXXX")"
NOTES="$TMP/zametki"          # как это лежит сегодня: папка заметок
VAULT="$TMP/vault"            # как это лежит после онбординга: Кортекс
cleanup () { [ "$KEEP" = 1 ] && echo "  стенды оставлены: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$NOTES" "$VAULT"

pass=0; fail=0
ok ()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad () { echo "  ✗ $1"; shift; printf '       %s\n' "$@"; fail=$((fail + 1)); }
hr ()  { echo "────────────────────────────────────────────────────────────────────────"; }
C ()   { "$VAULT/bin/cortex" --root "$VAULT" "$@" 2>&1; }

# Сколько заметок несут вычислимое поле. Текст — не поле: посчитать по нему
# нельзя, и в этом вся разница.
notes_with () { grep -rlE "$1" "$NOTES" 2>/dev/null | wc -l | tr -d ' '; }
# Обрезка по символам, а не по байтам: cut -c рвёт кириллицу пополам.
trim () { python3 -c "
import sys
for l in sys.stdin:
    l = l.rstrip(chr(10))
    print(l if len(l) <= 88 else l[:87] + chr(0x2026))"; }
# Показать, что найдёт поиск: файл, строка, текст.
found () {
  grep -rnE "$1" "$NOTES" 2>/dev/null | head -"${2:-3}" \
    | sed "s|^$NOTES/||" | trim | sed 's/^/      /'
}

OLD=$(python3 -c "import datetime;print(datetime.date.today()-datetime.timedelta(days=270))")
NOW=$(date +%F)

# ── стенд «до»: папка заметок реального PO ───────────────────────────────────
cat > "$NOTES/plan-kvartala.md" <<'EOF'
# План квартала

Цель: подключить трёх организаторов к витрине. Срок — 15 ноября,
дальше мимо сезона.

Зависим от: расчёты с организатором (финсистема), каталог мероприятий
(партнёр), возвраты и отмены (смежная команда).

Уверенность высокая, риски закрыли на кикоффе.
EOF

cat > "$NOTES/kikoff-minutki.md" <<'EOF'
# Кикофф витрины — минутки

- Объём: три организатора, продажа билетов через витрину.
- По срокам: к 15 ноября запускаемся, риски закрыты.
- Финсистема сказала, что успевает.
- Каталог — партнёр говорит, готов.
EOF

cat > "$NOTES/chat-smezhniki.txt" <<'EOF'
[10:12] я: по возвратам успеваем к ноябрю?
[10:14] техлид смежной команды: возвраты раньше декабря не обещаем, у нас свой релиз
[10:15] я: понял, вынесу на синк
[10:31] аналитик: каталог вроде готов, прогон был
EOF

cat > "$NOTES/speka-vitriny.md" <<'EOF'
# Спека витрины (черновик)

Организатор выкладывает мероприятие, получает деньги, обрабатывает возврат
без ручного участия поддержки.

Расчёты — по договорённости с финсистемой.
Возвраты — по контракту смежной команды, контракт не подписан.
EOF

cat > "$NOTES/pismo-katalog.md" <<EOF
# Письмо: прогон каталога ($OLD)

Прогнали 50 карточек против стенда партнёра — расхождений нет.
По остальным типам мероприятий не проверяли.
EOF

cat > "$NOTES/sozvon-finsistema.md" <<EOF
# Созвон с владельцем финсистемы ($NOW)

Расчёты с организатором делаем в этом квартале, объём понятен.
Подтверждение пришло письмом.
EOF

# ── стенд «после»: те же факты, записанные по правилам ───────────────────────
tar --exclude=.git --exclude=.github -cf - -C "$ROOT" . | tar -xf - -C "$VAULT"
C init --company "ООО Сравнение" --product "Витрина" --slug vitrina \
      --idea "Продажа билетов внешних организаторов через витрину." \
      --engineer "PO витрины" >/dev/null </dev/null

PROFILE=$(C profiles --json | python3 -c "
import json,sys
for p in json.load(sys.stdin):
    z = [w for w in (p.get('writes') or []) if w != 'org']
    if z: print(p['id'], z[0]); break" 2>/dev/null)
ZONE="${PROFILE#* }"; PROFILE="${PROFILE%% *}"
if [ -z "$PROFILE" ]; then
  echo "  ✗ в шаблоне нет ни одного профиля с зоной вне ядра — сравнение невозможно"
  exit 1
fi
C nexus add deps --name "Внешние зависимости" --scope org --owner PO \
  --types system --purpose "давать или не давать дату по чужой зоне" >/dev/null
C nexus add goals --name "Цели квартала" --scope "$ZONE" --owner PO \
  --types key-result --purpose "во что упирается цель" >/dev/null

# Зависимости живут в ядре организации: их заводит куратор, а не PO. Именно
# поэтому они и становятся стыком — своя цель упирается в чужую зону.
C node new --nexus deps --type system --title "Расчёты с организатором" \
  --owner "Владелец финсистемы" --change-rate medium --cp 3 \
  --source "email:владелец финсистемы — объём и дата, $NOW" >/dev/null
C node new --nexus deps --type system --title "Каталог мероприятий" \
  --owner "Аналитик партнёра" --change-rate low --cp 6 \
  --source "test:прогон против стенда партнёра, 50 карточек" >/dev/null
C node new --nexus deps --type system --title "Возвраты и отмены" \
  --owner "Техлид смежной команды" --change-rate high --cp 2 \
  --source "созвон: пересказ слов техлида смежной команды" >/dev/null
export CORTEX_PROFILE="$PROFILE"
C node new --nexus goals --type key-result --title "Подключены 3 организатора" \
  --owner "PO витрины" --change-rate low --cp 9 --scope "$ZONE" \
  --source "OKR департамента, утверждён на QBR" \
  --depends-on raschety-s-organizatorom --depends-on katalog-meropriyatiy \
  --depends-on vozvraty-i-otmeny >/dev/null

KR=podklyucheny-3-organizatora
# Прогон каталога был девять месяцев назад — как и письмо в папке заметок.
sed -i.bak "s/^updated: .*/updated: $OLD/" "$VAULT/GROUND/NEXUS/deps/katalog-meropriyatiy.md"
rm -f "$VAULT"/GROUND/NEXUS/deps/*.bak

# Ставка: PO написал ту же уверенность, что в минутках кикоффа — «риски закрыты».
cat > "$VAULT/GROUND/DECIDE/bets/zapusk.md" <<BET
---
node_id: bet-zapusk
node_type: bet
owner: PO витрины
gate: commit
stage: 4
threshold: 6
due: 2026-11-15
cp: 7
scope: $ZONE
impact_metric: "число подключённых организаторов, снимается из админки"
window: "до 15 ноября — иначе мимо сезона"
satisfies: [$KR]
depends_on: [raschety-s-organizatorom, katalog-meropriyatiy, vozvraty-i-otmeny]
non_critical: []
sources: ["OKR департамента"]
captured_by: human
updated: $NOW
---

## Что должно быть правдой

Организатор выкладывает мероприятие, получает деньги и обрабатывает возврат
без ручного участия поддержки. Периметр — запуск витрины с тремя организаторами.
BET

# Закрытые ставки прошлого квартала: без них калибровать лестницу не на чем.
mk_closed () {  # mk_closed <имя> <cp> <met|missed> <заголовок>
  cat > "$VAULT/GROUND/DECIDE/bets/$1.md" <<CLOSED
---
node_id: bet-$1
node_type: bet
owner: PO витрины
gate: commit
stage: 4
threshold: 6
due: 2026-06-30
cp: $2
outcome: $3
scope: $ZONE
sources: ["ретро квартала: $4"]
captured_by: human
updated: 2026-07-01
---

## Что должно быть правдой

$4
CLOSED
}
mk_closed q2-samovyvoz  3 missed "Самовывоз билетов работает у двух партнёров"
mk_closed q2-oplata     3 missed "Оплата картой стороннего банка проходит"
mk_closed q2-uvedomlen  3 missed "Уведомления об отмене доходят за 5 минут"
mk_closed q2-otchety    3 met    "Отчёт для организатора собирается сам"
mk_closed q2-lichkab    6 met    "Личный кабинет организатора в проде"
mk_closed q2-vozvrat    6 met    "Возврат по заявке закрывается за сутки"

C refresh >/dev/null

echo
echo "Сравнение: та же неделя работы PO, до Кортекса и после"
echo "  стенд «до»     — папка заметок: $(ls "$NOTES" | wc -l | tr -d ' ') файлов, те же факты"
echo "  стенд «после»  — Кортекс: 4 узла, 1 ставка на квартал, 6 закрытых ставок"
echo "  профиль: $PROFILE · зона: $ZONE"
echo

# ─────────────────────────────────────────────────────────────────────────────
hr; echo "Вопрос 1 из 6.  Успеем ли к 15 ноября?"; hr
echo
echo "  Без Кортекса — поиск по заметкам:"
found "15 ноября|раньше декабря" 4
DATES=$(grep -rlE "15 ноября|раньше декабря" "$NOTES" 2>/dev/null | wc -l | tr -d ' ')
echo "      → $DATES заметки отвечают по-разному. Какая свежее и какая весомее —"
echo "        из текста не выводится: ни у одной нет ни ступени, ни даты снятия."
echo
echo "  С Кортексом — cortex gate:"
OUT=$(C gate)
printf '%s\n' "$OUT" | grep -E "слабого звена|понизьте CP" | head -2 | sed 's/^/      /'
echo "      → обещание остановлено до того, как ушло наружу. Названо звено и число."
echo

if [ "$DATES" -ge 2 ] && [ "$(notes_with '^(cp|confidence|threshold):')" = 0 ]; then
  ok "«до»: $DATES разных ответа на один вопрос, 0 из них с основанием"
else
  bad "стенд «до» перестал быть «до»" \
      "ответов: $DATES (ждали ≥2), заметок со ступенью: $(notes_with '^(cp|confidence|threshold):') (ждали 0)"
fi
if printf '%s' "$OUT" | grep -q "выше слабого звена"; then
  ok "«после»: один ответ, и он назвал звено — $(printf '%s' "$OUT" | grep -o "CP 7 выше слабого звена.*" | head -1)"
else
  bad "«после»: гейт не остановил обещание выше слабого звена" "$(printf '%s' "$OUT" | tail -1)"
fi

# Дальше работаем с честной ставкой: CP опущен до потолка.
sed -i.bak 's/^cp: 7$/cp: 2/' "$VAULT/GROUND/DECIDE/bets/zapusk.md"
rm -f "$VAULT"/GROUND/DECIDE/bets/*.bak

# ─────────────────────────────────────────────────────────────────────────────
echo; hr; echo "Вопрос 2 из 6.  На чём держится цель квартала?"; hr
echo
echo "  Без Кортекса — поиск по заметкам:"
found "Зависим от|Цель:" 3
echo "      → зависимости перечислены словами, в одну строку и без веса."
echo "        связей, которые можно посчитать: $(notes_with '^(depends_on|satisfies):')"
echo
echo "  С Кортексом — cortex context --node $KR:"
CHAIN=$(C context --node "$KR" --json | python3 -c "
import json,sys
d = json.load(sys.stdin)
deps = [n for n in d['neighbours'] if n['field'] == 'depends_on']
for n in sorted(deps, key=lambda x: x['effective_cp'] or 9):
    print(f\"      {n['title'][:32]:32} CP {n['effective_cp']}  {n['ripeness']}  · {n['owner']}\")
print('COUNT', len(deps))
print('WEAK', min((n['effective_cp'] or 9) for n in deps) if deps else 9)" 2>/dev/null)
printf '%s\n' "$CHAIN" | grep -v "^COUNT\|^WEAK"
DEPN=$(printf '%s' "$CHAIN" | awk '/^COUNT/{print $2}')
WEAK=$(printf '%s' "$CHAIN" | awk '/^WEAK/{print $2}')
echo "      → потолок обещания виден числом: $WEAK. Выше него даты нет."
echo
if [ "$(notes_with '^(depends_on|satisfies):')" = 0 ]; then
  ok "«до»: 0 вычислимых связей — слабейшее звено назвать нечем"
else
  bad "у заметок появились поля связей — стенд «до» больше не «до»"
fi
if [ "${DEPN:-0}" -ge 3 ] && [ -n "$WEAK" ]; then
  ok "«после»: $DEPN связи посчитаны, слабейшая ступень названа: $WEAK"
else
  bad "«после»: цепочка цели не собралась" "связей: ${DEPN:-0}, слабейшая: ${WEAK:-—}"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo; hr; echo "Вопрос 3 из 6.  Что из этого уже неправда?"; hr
echo
echo "  Без Кортекса — письму про каталог девять месяцев:"
found "[Пп]рогон каталога" 2
echo "      → в папке оно выглядит ровно так же, как вчерашнее. Заметок,"
echo "        у которых есть срок годности: $(notes_with '^(ttl_days|ripeness|updated):')."
echo "        Устарело или нет — знает только память человека."
echo
echo "  С Кортексом — cortex stale:"
C stale | grep -E "Каталог|Очередь верификации" | head -2 | sed 's/^/      /'
EFF=$(grep -E '^effective_cp:' "$VAULT/GROUND/NEXUS/deps/katalog-meropriyatiy.md" | awk '{print $2}')
RIP=$(grep -E '^ripeness:'     "$VAULT/GROUND/NEXUS/deps/katalog-meropriyatiy.md" | awk '{print $2}')
echo "      → записано CP 6 по прогону на 50 карточках; сегодня effective_cp $EFF, $RIP."
echo "        Ступень упала сама, без обхода и без напоминания."
echo
if [ "$(notes_with '^(ttl_days|ripeness):')" = 0 ]; then
  ok "«до»: 0 заметок со сроком годности — старое неотличимо от свежего"
else
  bad "у заметок появился срок годности — стенд «до» больше не «до»"
fi
STALE=$(C stale)
if [ -n "$EFF" ] && [ "${EFF%%.*}" -lt 6 ] && [ "$RIP" = "wilting" ] \
   && printf '%s' "$STALE" | grep -q "Каталог"; then
  ok "«после»: CP 6 → effective_cp $EFF, $RIP, узел в очереди верификации"
else
  bad "«после»: распад не сработал" "effective_cp=$EFF ripeness=$RIP"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo; hr; echo "Вопрос 4 из 6.  Откуда это знание и можно ли на нём стоять?"; hr
echo
echo "  Без Кортекса — поиск по заметкам:"
found "вроде готов|говорит, готов" 2
echo "      → автор реплики есть, объёма проверки нет. Заметок, где источник"
echo "        записан полем: $(notes_with '^sources:'). Дописать «уверены на 90%» ничто не мешает."
echo
echo "  С Кортексом — cortex ask каталог:"
C ask каталог | grep -E "источник:|CP " | head -2 | sed 's/^/      /'
echo "      и попытка записать утверждение без источника:"
OUT=$(C node new --nexus deps --type system --title "Платёжный шлюз"); CODE=$?
printf '%s\n' "$OUT" | tail -1 | trim | sed 's/^/      /'
echo
if [ "$(notes_with '^sources:')" = 0 ]; then
  ok "«до»: 0 заметок с источником-полем — объём утверждения не зафиксирован"
else
  bad "у заметок появилось поле источника — стенд «до» больше не «до»"
fi
if [ "$CODE" != 0 ] && ! printf '%s' "$OUT" | grep -q "Traceback (most recent call last)" \
   && printf '%s' "$OUT" | grep -qE "source|источник"; then
  ok "«после»: запись без источника отклонена, причина названа"
else
  bad "«после»: утверждение без источника прошло" "$(printf '%s' "$OUT" | tail -1)"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo; hr; echo "Вопрос 5 из 6.  Во что упирается моя работа и кому писать?"; hr
echo
echo "  Без Кортекса — поиск по заметкам:"
found "техлид|финсистем" 3
echo "      → роли упомянуты в тексте. Заметок, где владелец записан полем:"
echo "        $(notes_with '^owner:'). Спросить «кто отвечает за возвраты» можно только человека."
echo
echo "  С Кортексом — cortex seams:"
SEAMS=$(C seams)
printf '%s\n' "$SEAMS" | sed -n '/Наружу/,$p' | grep -v '^[[:space:]]*$' | sed -n '3,6p' | trim | sed 's/^/     /'
echo "  и cortex who возвраты:"
C who возвраты | grep -v "Кому писать" | head -2 | sed 's/^/      /'
echo "      → кому писать и чем это кончится для даты — видно без человека,"
echo "        который помнит, кто за что отвечает."
echo
if [ "$(notes_with '^owner:')" = 0 ]; then
  ok "«до»: 0 заметок с владельцем-полем — адресат собирается по памяти"
else
  bad "у заметок появился владелец-поле — стенд «до» больше не «до»"
fi
OWNERS=$(C who возвраты --json | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null)
if printf '%s' "$SEAMS" | grep -q "чужая зона" && [ "${OWNERS:-0}" -ge 1 ]; then
  ok "«после»: стык наружу показан, владелец найден ($OWNERS)"
else
  bad "«после»: стыки или владелец не собрались" "стыки: $(printf '%s' "$SEAMS" | grep -c 'чужая зона'), владельцев: ${OWNERS:-0}"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo; hr; echo "Вопрос 6 из 6.  В чём мы были уверены в прошлом квартале — и не сработало?"; hr
echo
echo "  Без Кортекса:"
echo "      обещаний прошлого квартала, записанных с уверенностью и исходом:"
echo "        $(notes_with '^outcome:'). Вопрос не задаётся — отвечать не на чем."
echo
echo "  С Кортексом — cortex calibrate:"
CAL=$(C calibrate)
printf '%s\n' "$CAL" | sed -n '/Лестница против исходов/,/^$/p' | sed 's/^/      /'
printf '%s\n' "$CAL" | grep -E "из .* обещаний доехало|сдвиньте формулировку" | sed 's/^/      /'
echo "      → это не отчёт о прошлом, а правка линейки, которой меряют будущее."
echo
if [ "$(notes_with '^outcome:')" = 0 ]; then
  ok "«до»: 0 закрытых обещаний в проверяемом виде — калибровать нечего"
else
  bad "у заметок появился исход-поле — стенд «до» больше не «до»"
fi
# Проверяем вывод самого инструмента, а не свой пересчёт его же данных:
# иначе проверка подтвердит арифметику и пропустит сломанную калибровку.
CLOSED=$(C calibrate --json | python3 -c "
import json,sys
print(sum(r['met'] + r['missed'] for r in json.load(sys.stdin)['ladder']))" 2>/dev/null)
if [ "${CLOSED:-0}" -ge 3 ] && printf '%s' "$CAL" | grep -q "переоценённые ступени"; then
  ok "«после»: по $CLOSED закрытым обещаниям инструмент сам назвал переоценённую ступень"
else
  bad "«после»: калибровка не назвала переоценённую ступень" \
      "закрытых ставок в выборке: ${CLOSED:-0}, вывод: $(printf '%s' "$CAL" | grep -c 'переоценённые ступени')"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo; hr
echo "Что изменилось, одной таблицей"
hr
python3 - "$DATES" "$DEPN" "$WEAK" "$EFF" "$RIP" <<'TBL'
import sys
d, n, w, eff, rip = sys.argv[1:6]
rows = [("вопрос", "до", "после"),
        ("успеем ли к дате",        f"{d} ответа",   "1 ответ + звено и число"),
        ("на чём держится цель",    "0 связей",      f"{n} связи, потолок {w}"),
        ("что уже неправда",        "не видно",      f"CP 6 → {eff}, {rip}"),
        ("откуда знание",           "0 источников",  "источник у каждого узла"),
        ("кому писать",             "0 владельцев",  "владелец и стык наружу"),
        ("где мы переоценили себя", "не спросить",   "ступень найдена по исходам")]
for a, b, c in rows:
    print(f"  {a:<26}{b:<15}{c}")
TBL
echo
echo "  Ни одна строка не про объём поставки. Все шесть — про управляемость:"
echo "  разрыв виден в начале квартала, а не в конце."
echo
echo "  Чего этот тест НЕ доказывает: что квартал станет лучше. Это проверяется"
echo "  на квартале, пятью метриками — docs/comparison.md, раздел «Замеры»."

echo
if [ "$fail" = 0 ]; then
  echo "✓ сравнение пройдено: $pass проверок — разница измерима с обеих сторон"
else
  echo "✗ сравнение провалено: $fail из $((pass + fail))"
  exit 1
fi
