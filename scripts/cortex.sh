#!/usr/bin/env bash
# Cortex — единая точка входа в vault организации.
#
#   ./scripts/cortex.sh init      заполнить GROUND/config.yaml и привязать vault к себе
#   ./scripts/cortex.sh gate      проверить память: схема, рёбра, свежесть  (перед каждым коммитом)
#   ./scripts/cortex.sh report    отчёт: узлы, рёбра, Context Ripeness по Нексусам
#   ./scripts/cortex.sh gaps      дыры и достижимость контента от хребта OKR
#   ./scripts/cortex.sh build     сгенерировать узлы OKR/PULSE и записать рёбра в frontmatter
#   ./scripts/cortex.sh engine    поставить/обновить движок памяти (poh-memory-engine)
#
# Требуется: bash, git, python3. Движок ставится в .engine/ (в .gitignore).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ENGINE_DIR="${CORTEX_ENGINE_DIR:-$ROOT/.engine}"
ENGINE_URL="${CORTEX_ENGINE_URL:-https://github.com/po-helper-org/poh-memory-engine}"
GROUND="$ROOT/GROUND"

c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
c_dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
die()    { c_red "✗ $*"; exit 1; }

need_python () {
  command -v python3 >/dev/null 2>&1 || die "нужен python3"
  if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    c_dim "  ставлю PyYAML…"
    python3 -m pip install --quiet --user PyYAML >/dev/null 2>&1 || true
    python3 -c 'import yaml' >/dev/null 2>&1 \
      || die "нужен PyYAML: python3 -m pip install --user PyYAML"
  fi
}

ensure_engine () {
  command -v git >/dev/null 2>&1 || die "нужен git"
  if [ ! -d "$ENGINE_DIR/.git" ]; then
    c_dim "  тяну движок памяти: $ENGINE_URL → .engine/"
    git clone --depth 1 --quiet "$ENGINE_URL" "$ENGINE_DIR" \
      || die "не удалось клонировать движок. Проверьте доступ к $ENGINE_URL"
  fi
  need_python
  export PYTHONPATH="$ENGINE_DIR${PYTHONPATH:+:$PYTHONPATH}"
}

# Значение из GROUND/config.yaml по точечному пути; пусто, если нет.
cfg () {
  python3 - "$1" "$GROUND/config.yaml" <<'PY'
import sys, pathlib
try:
    import yaml
except ImportError:
    sys.exit(0)
p = pathlib.Path(sys.argv[2])
if not p.exists():
    sys.exit(0)
cur = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
for part in sys.argv[1].split("."):
    if not isinstance(cur, dict):
        sys.exit(0)
    cur = cur.get(part)
    if cur is None:
        sys.exit(0)
print(cur)
PY
}

# Окружение движка: корень vault, квартал, владелец по умолчанию.
engine_env () {
  export POH_VAULT="$ROOT"
  export POH_QUARTER="${POH_QUARTER:-$(python3 -c 'import datetime as d;t=d.date.today();print(f"q{(t.month-1)//3+1}-{t.year}")')}"
  if [ -z "${POH_DEFAULT_OWNER:-}" ]; then
    owner="$(cfg team.roster.product_engineer || true)"
    export POH_DEFAULT_OWNER="${owner:-Product Engineer}"
  fi
}

# --- init ---------------------------------------------------------------------

cmd_init () {
  [ -f "$GROUND/config.yaml" ] || die "нет GROUND/config.yaml — вы точно в корне Кортекса?"
  need_python

  echo "Инициализация Кортекса. Пустой ответ оставляет плейсхолдер."
  echo

  ask () {  # ask <переменная-окружения> <подсказка> <текущее>
    local envval="${!1:-}" ans=""
    if [ -n "$envval" ]; then printf '%s' "$envval"; return; fi
    if [ -t 0 ]; then read -r -p "  $2: " ans; fi
    printf '%s' "$ans"
  }

  company="$(ask CORTEX_COMPANY   'Организация')"
  product="$(ask CORTEX_PRODUCT   'Продукт')"
  slug="$(ask    CORTEX_SLUG      'Slug продукта (a-z0-9-)')"
  idea="$(ask    CORTEX_IDEA      'Идея продукта одной фразой')"
  engineer="$(ask CORTEX_ENGINEER 'Продуктовый инженер (имя)')"

  if [ -n "$slug" ] && ! printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
    die "slug '$slug' не подходит: только [a-z0-9-], начинается с буквы или цифры"
  fi

  COMPANY="$company" PRODUCT="$product" SLUG="$slug" IDEA="$idea" ENGINEER="$engineer" \
  python3 - <<'PY'
import os, pathlib, re, datetime

root = pathlib.Path(".")
cfg = root / "GROUND" / "config.yaml"
text = cfg.read_text(encoding="utf-8")
today = datetime.date.today().isoformat()

def sub(pattern, repl, text, value):
    if not value:
        return text, False
    new, n = re.subn(pattern, repl.replace("@@", value.replace("\\", "\\\\")), text,
                     count=1, flags=re.M)
    return new, bool(n)

changed = []
for pattern, repl, value, label in [
    (r'^company: .*$',              'company: "@@"',              os.environ["COMPANY"],  "company"),
    (r'^  name: .*$',               '  name: "@@"',               os.environ["PRODUCT"],  "product.name"),
    (r'^  slug: .*$',               '  slug: @@',                 os.environ["SLUG"],     "product.slug"),
    (r'^    product_engineer: .*$', '    product_engineer: "@@"', os.environ["ENGINEER"], "roster.product_engineer"),
]:
    text, ok = sub(pattern, repl, text, value)
    if ok:
        changed.append(label)

idea = os.environ["IDEA"].strip()
if idea:
    text, ok = re.subn(r'^  idea: >\n(?:    .*\n)+', f'  idea: >\n    {idea}\n', text,
                       count=1, flags=re.M)
    if ok:
        changed.append("product.idea")

text = re.sub(r'^created: .*$', f'created: {today}', text, count=1, flags=re.M)
changed.append("created")
cfg.write_text(text, encoding="utf-8")

# Свежесть узлов: дата шаблона → сегодня, чтобы ripeness не врал с первого дня.
touched = 0
for p in sorted((root / "GROUND").rglob("*.md")):
    t = p.read_text(encoding="utf-8")
    n = re.subn(r'^updated: \d{4}-\d{2}-\d{2}\s*$', f'updated: {today}', t, flags=re.M)
    if n[1]:
        p.write_text(n[0], encoding="utf-8")
        touched += 1

print("  обновлено в config.yaml: " + (", ".join(changed) if changed else "ничего"))
print(f"  дата updated выставлена на {today} в {touched} узлах")
PY

  echo
  c_grn "✓ vault привязан к вашей организации"
  echo
  echo "Дальше:"
  echo "  1. Отвяжите репозиторий от шаблона, если клонировали его напрямую:"
  c_dim  "       git remote set-url origin <URL вашего репозитория>"
  echo "  2. Запустите Claude Code в этой папке и выполните онбординг:"
  c_dim  "       /paf-onboard"
  echo "  3. Проверьте память:"
  c_dim  "       ./scripts/cortex.sh gate"
  echo
  c_ylw "Заполните GROUND/config.yaml до конца (roster, cortex.phase_target) и VISION.md."
}

# --- gate ---------------------------------------------------------------------

cmd_gate () {
  ensure_engine
  if python3 - "$GROUND" <<'PY'
import sys, pathlib, re
from sa_documentation.validate_ground import validate_ground, lint_nodes, _registry_slugs

ground = pathlib.Path(sys.argv[1])

struct = validate_ground(str(ground))
# Линтуем только NEXUS: PULSE/summaries — эпизоды в своём формате, не Node schema.
nodes = lint_nodes(str(ground / "NEXUS"), registry_slugs=_registry_slugs(str(ground)))

errors = [i for i in nodes if i.startswith("ERROR")]
warns  = [i for i in nodes if i.startswith("WARN")]

print("== СТРУКТУРА (config + registry) ==")
print("\n".join(struct) or "OK")
print(f"\n== УЗЛЫ == ({len(errors)} ошибок, {len(warns)} предупреждений)")
print("\n".join(nodes) or "OK")

# Незаменённые плейсхолдеры — не ошибка схемы, а список незакрытого онбординга.
ph = []
for p in [ground / "config.yaml", pathlib.Path("VISION.md")]:
    if p.exists():
        rel = p.relative_to(pathlib.Path.cwd()) if p.is_absolute() else p
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r'<[^<>]{2,}>', line) and not line.lstrip().startswith(("#", ">", "|")):
                ph.append(f"{rel}:{i}: {line.strip()[:70]}")
if ph:
    print(f"\n== ПЛЕЙСХОЛДЕРЫ == ({len(ph)} не заменено)")
    print("\n".join(ph[:20]))

sys.exit(1 if (struct or errors) else 0)
PY
  then
    c_grn "✓ гейт зелёный — можно коммитить"
  else
    c_red "✗ гейт красный — чините ошибки выше, коммит не пройдёт CI"
    return 1
  fi
}

# --- движок -------------------------------------------------------------------

cmd_engine () {
  ensure_engine
  ( cd "$ENGINE_DIR" && git pull --quiet --ff-only 2>/dev/null || true )
  c_grn "✓ движок памяти готов: $ENGINE_DIR"
  c_dim "  дальше: ./scripts/cortex.sh report"
}

run_paf () {
  ensure_engine
  engine_env
  c_dim "  vault=$POH_VAULT quarter=$POH_QUARTER owner=$POH_DEFAULT_OWNER"
  ( cd "$ROOT" && python3 -m paf_index "$1" )
}

# --- диспетчер ----------------------------------------------------------------

case "${1:-help}" in
  init)   cmd_init ;;
  gate)   cmd_gate ;;
  engine) cmd_engine ;;
  report) run_paf report ;;
  gaps)   run_paf gaps ;;
  build)  run_paf build ;;
  help|-h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}" ;;
  *)      die "неизвестная команда '${1}'. Смотрите: ./scripts/cortex.sh help" ;;
esac
