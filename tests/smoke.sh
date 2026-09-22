#!/usr/bin/env bash
# Дымовой тест Кортекса. Без сети, без зависимостей: bash + python3.
#   tests/smoke.sh            на этом репозитории
#   tests/smoke.sh /путь      на любом другом vault
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="${1:-$ROOT}"
pass=0; fail=0

check () {  # check <описание> <ожидаемый-код> <аргументы cortex...>
  local desc="$1" want="$2"; shift 2
  local out code
  out=$("$ROOT/bin/cortex" --root "$VAULT" "$@" 2>&1)
  code=$?
  if [ "$code" = "$want" ]; then
    echo "  ok   $desc"
    pass=$((pass + 1))
  else
    echo "  FAIL $desc (код $code, ждали $want)"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    fail=$((fail + 1))
  fi
}

echo "Кортекс — дымовой тест: $VAULT"
check "doctor отвечает"              0 doctor
check "схема читается"               0 schema show
check "гейт проходит"                0 gate
check "свежесть пересчитана"         0 refresh --dry-run
check "отчёт собирается"             0 report
check "поиск отвечает"               0 ask продукт
check "очередь читается"             0 intake list
check "зоны агентов видны"           0 agents
check "сироты считаются"             0 gaps
check "узел без источника отклонён"  2 node new --nexus product --type feature --title "Без источника"
check "чужой Нексус отклонён"        2 node new --nexus nope --type feature --title x --source y
check "висячее ребро отклонено"      2 node new --nexus product --type feature --title x --source y --satisfies kr-нет
check "неизвестный тип отклонён"     2 node new --nexus product --type выдумка --title x --source y
check "профили перечислены"          0 profiles
check "очередь приёмки отвечает"     0 review
check "неизвестный профиль отклонён" 2 --as нет-такого profiles
check "срез без профиля отклонён"    2 pack --stdout
check "срезы всех профилей"          0 pack --all

# Значение берём из самого vault: тест не знает, как их назвали у вас.
# Три исхода различаются намеренно: успех, пустой результат (штатный пропуск)
# и сбой чтения или разбора — провал. Молча пропущенная проверка выглядит как
# пройденная, а это худший вид зелёного.
read_json () {  # read_json <что читаем> <python-выражение> <аргументы cortex...>
  local what="$1" expr="$2"; shift 2
  local raw parsed
  if ! raw=$("$ROOT/bin/cortex" --root "$VAULT" "$@" 2>&1); then
    echo "  FAIL $what: команда завершилась с ошибкой"
    printf '%s\n' "$raw" | tail -1 | sed 's/^/       /'
    fail=$((fail + 1))
    READ_JSON=""; READ_OK=0
    return 1
  fi
  if ! parsed=$(printf '%s' "$raw" | python3 -c "$expr" 2>&1); then
    echo "  FAIL $what: JSON не разобрался — изменился формат вывода?"
    printf '%s\n' "$parsed" | tail -1 | sed 's/^/       /'
    fail=$((fail + 1))
    READ_JSON=""; READ_OK=0
    return 1
  fi
  READ_JSON="$parsed"; READ_OK=1
}

read_json "профили" \
  "import json,sys;d=json.load(sys.stdin);print(d[0]['id'] if d else '')" \
  profiles --json
PROFILE="$READ_JSON"
if [ -n "$PROFILE" ]; then
  check "профиль не пишет в ядро"      2 --as "$PROFILE" node new --nexus team --type person --title X --source y --scope org
  check "профиль не пишет в чужую зону" 2 --as "$PROFILE" node new --nexus product --type feature --title X --source y --scope "team:посторонняя"
  check "стыки считаются"              0 --as "$PROFILE" seams
  check "--as после подкоманды"        0 seams --as "$PROFILE"
  check "срез профиля собирается"      0 --as "$PROFILE" pack --stdout
elif [ "$READ_OK" = 1 ]; then
  echo "  --   профилей не объявлено: проверки зон пропущены (это штатно)"
else
  echo "  --   профили прочитать не удалось: проверки зон НЕ выполнены"
fi
check "повестка дня собирается"      0 agenda
check "расхождения ищутся"           0 conflicts
check "калибровка считается"         0 calibrate
# Узел берём из самого vault: тест не должен знать чужое содержимое.
# Нужен узел знания (NEXUS), а не операционная запись: резолвер отвечает про
# сущности, а не про дневник, и ступень должна быть ниже девятой, чтобы
# проверка отказа на росте CP имела смысл.
read_json "узлы знания" "import json,sys
d = json.load(sys.stdin)['answer_from']
print(next((x['node_id'] for x in d
            if x.get('node_id') and x.get('cp') is not None and x['cp'] < 9
            and 'NEXUS/' in (x.get('path') or '')), ''))" \
  ask память продукт цель --json
NODE="$READ_JSON"
if [ -n "$NODE" ]; then
  check "проверка узла отвечает"       0 node check "$NODE"
  check "рост CP без источника отклонён" 2 node set "$NODE" --cp 9
  # Спор снимают только новым источником — узел существует, значит отказ
  # будет именно по этой причине, а не из-за ненайденного id.
  check "снятие спора без источника"   2 conflicts --resolve "$NODE"
  # Резолвер должен именно НАХОДИТЬ, а не просто завершаться успешно.
  if "$ROOT/bin/cortex" --root "$VAULT" resolve "$NODE" --json 2>/dev/null \
       | python3 -c "import json,sys;sys.exit(0 if json.load(sys.stdin) else 1)"; then
    echo "  ok   резолвер находит узел по имени"
    pass=$((pass + 1))
  else
    echo "  FAIL резолвер не нашёл существующий узел"
    fail=$((fail + 1))
  fi
elif [ "$READ_OK" = 1 ]; then
  echo "  --   узлов знания нет: проверки контракта обновления пропущены (это штатно)"
else
  echo "  --   узлы прочитать не удалось: проверки контракта НЕ выполнены"
fi

echo
if [ "$fail" = 0 ]; then
  echo "✓ всё зелёное: $pass проверок"
else
  echo "✗ провалов: $fail из $((pass + fail))"
  exit 1
fi
