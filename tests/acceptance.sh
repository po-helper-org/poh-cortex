#!/usr/bin/env bash
# Приёмка Кортекса: убедиться, что инструмент действительно работает.
#
# Дымовой тест (tests/smoke.sh) отвечает на вопрос «команды не падают».
# Приёмка отвечает на другой: **делает ли Кортекс то, ради чего он есть** —
# отказывается записывать утверждение без источника, не даёт поднять
# уверенность рассуждением, роняет её сама при протухании и не пускает
# обещание выше слабого звена.
#
# Проверяется не код возврата, а ПРИЧИНА отказа: команда, упавшая по другому
# поводу, зачтена не будет. Отказ за неверную причину — худший вид зелёного.
#
#   tests/acceptance.sh          собрать временный vault и прогнать приёмку
#   tests/acceptance.sh --keep   не удалять временный vault (посмотреть файлы)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1

VAULT="$(mktemp -d "${TMPDIR:-/tmp}/cortex-acceptance.XXXXXX")"
cleanup () { [ "$KEEP" = 1 ] && echo "  vault оставлен: $VAULT" || rm -rf "$VAULT"; }
trap cleanup EXIT

pass=0; fail=0; skip=0
C () { "$VAULT/bin/cortex" --root "$VAULT" "$@" 2>&1; }

ok ()   { echo "  ✓ $1"; pass=$((pass + 1)); }
bad ()  { echo "  ✗ $1"; shift; printf '       %s\n' "$@"; fail=$((fail + 1)); }
none () { echo "  —  $1"; skip=$((skip + 1)); }

# refuses <что проверяем> <regexp причины> -- <аргументы cortex...>
refuses () {
  local what="$1" why="$2"; shift 3
  local out code
  out=$(C "$@"); code=$?
  if [ "$code" = 0 ]; then
    bad "$what: команда НЕ отказала" "$(printf '%s' "$out" | tail -1)"
  elif printf '%s' "$out" | grep -q "Traceback (most recent call last)"; then
    # Падение — не отказ. Инструмент обязан назвать причину, а не уронить стек:
    # иначе «отказал» засчитывается за краш, и приёмка зеленеет на сломанном коде.
    bad "$what: инструмент упал вместо отказа" "$(printf '%s' "$out" | tail -1)"
  elif ! printf '%s' "$out" | grep -qE "$why"; then
    bad "$what: отказала, но не по той причине" \
        "ждали: /$why/" "получили: $(printf '%s' "$out" | tail -1)"
  else
    ok "$what"
  fi
}

# accepts <что проверяем> -- <аргументы cortex...>
accepts () {
  local what="$1"; shift 2
  local out code
  out=$(C "$@"); code=$?
  if [ "$code" != 0 ]; then
    bad "$what: команда отказала, хотя основание есть" "$(printf '%s' "$out" | tail -1)"
  elif printf '%s' "$out" | grep -q "Traceback (most recent call last)"; then
    bad "$what: инструмент упал" "$(printf '%s' "$out" | tail -1)"
  else
    ok "$what"
  fi
}

echo "Приёмка Кортекса"
echo "  шаблон: $ROOT"
echo

# ── стенд ────────────────────────────────────────────────────────────────────
# Копия шаблона без .git: приёмка никогда не трогает вашу память.
tar --exclude=.git --exclude=.github -cf - -C "$ROOT" . | tar -xf - -C "$VAULT"

C init --company "ООО Приёмка" --product "Витрина" --slug vitrina \
      --idea "Продажа билетов внешних организаторов через витрину." \
      --engineer "Иванов И." >/dev/null </dev/null

# Профиль и его зона берутся из шаблона: тест не знает, как их назвали у вас.
PROFILE=$(C profiles --json | python3 -c "
import json,sys
for p in json.load(sys.stdin):
    z = [w for w in (p.get('writes') or []) if w != 'org']
    if z: print(p['id'], z[0]); break" 2>/dev/null)
ZONE="${PROFILE#* }"; PROFILE="${PROFILE%% *}"
if [ -z "$PROFILE" ]; then
  echo "  ✗ в шаблоне нет ни одного профиля с зоной вне ядра — приёмка невозможна"
  exit 1
fi
export CORTEX_PROFILE="$PROFILE"
echo "  профиль: $PROFILE · зона: $ZONE"
echo

C nexus add deps --name "Внешние зависимости" --scope org --owner PO \
  --types system --purpose "давать или не давать дату по чужой зоне" >/dev/null
C nexus add goals --name "Цели квартала" --scope "$ZONE" --owner PO \
  --types key-result --purpose "во что упирается цель" >/dev/null

C node new --nexus goals --type key-result --title "Подключены 3 организатора" \
  --source "OKR департамента, утверждён на QBR" --cp 9 --change-rate low --scope "$ZONE" >/dev/null
C node new --nexus deps --type system --title "Расчёты с организатором" \
  --source "email:владелец финсистемы, объём и дата" --cp 3 --change-rate medium >/dev/null
C node new --nexus deps --type system --title "Каталог мероприятий" \
  --source "test:прогон против стенда партнёра, 50 карточек" --cp 6 --change-rate low >/dev/null
C node new --nexus deps --type system --title "Возвраты и отмены" \
  --source "созвон: слова техлида смежной команды" --cp 2 --change-rate high >/dev/null

KR=$(C ask организатор --json | python3 -c "
import json,sys
print(next(x['node_id'] for x in json.load(sys.stdin)['answer_from']
           if x.get('type') == 'key-result'))" 2>/dev/null)

cat > "$VAULT/GROUND/DECIDE/bets/zapusk.md" <<BET
---
node_id: bet-zapusk
node_type: bet
owner: Иванов И.
gate: commit
stage: 4
threshold: 6
due: 2026-11-15
cp: 2
scope: "запуск витрины с тремя организаторами"
impact_metric: "число подключённых организаторов, снимается из админки"
window: "до 15 ноября — иначе мимо сезона"
satisfies: [$KR]
depends_on: [raschety-s-organizatorom, katalog-meropriyatiy, vozvraty-i-otmeny]
non_critical: []
sources: ["OKR департамента"]
captured_by: human
updated: $(date +%F)
---

## Что должно быть правдой

Организатор выкладывает мероприятие, получает деньги и обрабатывает возврат
без ручного участия поддержки.
BET

# ── приёмка ──────────────────────────────────────────────────────────────────
echo "Что Кортекс отказывается делать"
refuses "утверждение без источника не записывается" \
        "source|источник" -- \
        node new --nexus deps --type system --title "Платёжный шлюз"

refuses "уверенность не поднимается рассуждением" \
        "нового источника|--source" -- \
        node set vozvraty-i-otmeny --cp 7

refuses "профиль не пишет в ядро организации" \
        "не пишет в зону|зоны:" -- \
        node new --nexus team --type person --title "Петров П." \
        --source "оргструктура" --scope org

refuses "Нексус, не объявленный в реестре, не принимает записи" \
        "не объявлен|нет в реестре|Нексус" -- \
        node new --nexus nosuchnexus --type system --title X --source y

echo
echo "Что Кортекс делает"
accepts "та же ступень с артефактом — принимается" -- \
        node set vozvraty-i-otmeny --cp 6 \
        --source "test:сквозной прогон возврата против стенда смежников"

# Распад. Дату правим напрямую: это одноразовый стенд, и проверяем мы ровно то,
# что инструмент понижает уверенность сам, без участия человека.
sed -i.bak 's/^updated: .*/updated: 2020-01-01/' \
  "$VAULT/GROUND/NEXUS/deps/vozvraty-i-otmeny.md" && rm -f "$VAULT"/GROUND/NEXUS/deps/*.bak
C refresh >/dev/null
EFF=$(grep -E '^effective_cp:' "$VAULT/GROUND/NEXUS/deps/vozvraty-i-otmeny.md" | awk '{print $2}')
RIP=$(grep -E '^ripeness:' "$VAULT/GROUND/NEXUS/deps/vozvraty-i-otmeny.md" | awk '{print $2}')
if [ "$RIP" = "wilting" ] && [ -n "$EFF" ] && [ "${EFF%%.*}" -lt 6 ]; then
  ok "протухшее знание теряет ступень само: cp 6 → effective_cp $EFF, $RIP"
else
  bad "распад не сработал" "ripeness=$RIP effective_cp=$EFF (ждали wilting и < 6)"
fi

OUT=$(C stale)
if printf '%s' "$OUT" | grep -q "Возвраты"; then
  ok "протухшее попало в очередь верификации"
else
  bad "cortex stale не показал протухший узел"
fi

echo
echo "Что Кортекс считает за вас"
OUT=$(C gate)
if printf '%s' "$OUT" | tail -1 | grep -q "зелёный"; then
  ok "ставка с CP 2 на зависимостях 3 · 6 · 2 — гейт зелёный"
else
  bad "гейт красный там, где ставка не превышает слабое звено" "$(printf '%s' "$OUT" | tail -1)"
fi

sed -i.bak 's/^cp: 2$/cp: 7/' "$VAULT/GROUND/DECIDE/bets/zapusk.md" && rm -f "$VAULT"/GROUND/DECIDE/bets/*.bak
OUT=$(C gate)
if printf '%s' "$OUT" | grep -q "выше слабого звена"; then
  ok "обещание выше слабого звена остановлено: $(printf '%s' "$OUT" | grep -o "CP 7 выше слабого звена.*" | head -1)"
else
  bad "CP ставки выше слабейшей зависимости прошёл гейт" "$(printf '%s' "$OUT" | tail -1)"
fi
sed -i.bak 's/^cp: 7$/cp: 2/' "$VAULT/GROUND/DECIDE/bets/zapusk.md" && rm -f "$VAULT"/GROUND/DECIDE/bets/*.bak

# Побочная зависимость выносится из потолка явно — и только явно.
sed -i.bak 's/^cp: 2$/cp: 3/; s/^non_critical: \[\]$/non_critical: [vozvraty-i-otmeny]/' \
  "$VAULT/GROUND/DECIDE/bets/zapusk.md" && rm -f "$VAULT"/GROUND/DECIDE/bets/*.bak
OUT=$(C gate)
if printf '%s' "$OUT" | tail -1 | grep -q "зелёный"; then
  ok "зависимость в non_critical потолок не держит: CP 3 при слабейшей 2 — гейт зелёный"
else
  bad "non_critical не исключает зависимость из потолка" "$(printf '%s' "$OUT" | tail -1)"
fi

# Опечатка в non_critical вернула бы зависимость в критические молча.
sed -i.bak 's/^non_critical: \[vozvraty-i-otmeny\]$/non_critical: [vozvraty-i-otmen]/' \
  "$VAULT/GROUND/DECIDE/bets/zapusk.md" && rm -f "$VAULT"/GROUND/DECIDE/bets/*.bak
OUT=$(C gate)
if printf '%s' "$OUT" | grep -q "нет среди depends_on"; then
  ok "опечатка в non_critical поймана, а не проглочена"
else
  bad "опечатка в non_critical прошла молча" "$(printf '%s' "$OUT" | tail -1)"
fi
sed -i.bak 's/^non_critical: .*$/non_critical: []/; s/^cp: 3$/cp: 2/' \
  "$VAULT/GROUND/DECIDE/bets/zapusk.md" && rm -f "$VAULT"/GROUND/DECIDE/bets/*.bak

echo
echo "Ради чего всё: на чём стоит цель"
C context --kr "$KR" --json | python3 -c "
import json,sys
d = json.load(sys.stdin); w = d.get('weakest') or {}
print(f\"  цель  «{d['kr']['title']}»  CP {d['kr']['effective_cp']}   ← утверждена\")
print(f\"  стоит на  {w.get('node_id','—')}  CP {w.get('effective_cp','—')}   ← чем подтверждена\")
print()
print('  Разрыв между этими двумя строками виден в начале квартала, а не в конце.')
" 2>/dev/null || echo "  (не удалось собрать контекст цели)"

echo
if [ "$fail" = 0 ]; then
  echo "✓ приёмка пройдена: $pass проверок${skip:+, пропущено $skip}"
else
  echo "✗ приёмка провалена: $fail из $((pass + fail))"
  exit 1
fi
