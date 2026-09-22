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
check "резолвер отвечает"            0 resolve контракт агентов
check "неизвестный профиль отклонён" 2 --as нет-такого profiles
check "профиль не пишет в ядро"      2 --as po-gds node new --nexus team --type person --title X --source y --scope org
check "профиль не пишет в чужую зону" 2 --as po-gds node new --nexus product --type feature --title X --source y --scope team:Live
# Узел берём из самого vault: тест не должен знать чужое содержимое.
NODE=$("$ROOT/bin/cortex" --root "$VAULT" ask память продукт цель --json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['answer_from'];print(next((x['node_id'] for x in d if x.get('node_id') and x.get('cp') is not None and x['cp']<9),''))" 2>/dev/null)
if [ -n "$NODE" ]; then
  check "проверка узла отвечает"       0 node check "$NODE"
  check "рост CP без источника отклонён" 2 node set "$NODE" --cp 9
else
  echo "  --   узлов для проверки контракта обновления нет (пустая память)"
fi

echo
if [ "$fail" = 0 ]; then
  echo "✓ всё зелёное: $pass проверок"
else
  echo "✗ провалов: $fail из $((pass + fail))"
  exit 1
fi
