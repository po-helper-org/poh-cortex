# poh-cortex — Кортекс организации

## Что это

Клонируемый репозиторий **продуктовой памяти организации**, устроенный по
методологии [PAF](https://productframework.ru/ops/main). Markdown в git —
носитель истины; граф и вектор — пересобираемые артефакты.

Не документация о продукте, а **цифровой профиль организации**: кто мы, для
кого, чем защищены, к каким целям движемся — узлами графа с источниками,
уверенностью (Confidence Point) и сроком годности.

## Для чего

Чтобы **ИИ-агент получал навыки для принятия хороших управленческих решений и
контроля бизнес-процессов**: он работает не на общих соображениях, а на памяти
организации — с проверяемыми источниками, честной уверенностью и привязкой к
целям квартала.

Репозиторий приезжает пустым и валидным: методология внутри, ваш контекст — нет.
Агент получает контракт (`AGENTS.md`) и скиллы онбординга, память — гейт,
который не пускает выдумки.

---

## QuickStart

**0. Изучить методологию и принципы** — https://productframework.ru/ops/main

Нексус, Кортекс, Confidence Point, спелость контекста, банч вместо беклога.
Короткая выжимка — [docs/paf-methodology.md](docs/paf-methodology.md).

**1. Открыть репозиторий** — https://github.com/po-helper-org/poh-cortex

Через GitHub: **Use this template** → новый репозиторий. Или руками:

```bash
git clone https://github.com/po-helper-org/poh-cortex my-cortex
cd my-cortex
git remote set-url origin <URL вашего репозитория>
```

**2. Выполнить команду инициализации**

```bash
./scripts/cortex.sh init
```

Спросит организацию, продукт, slug, идею и продуктового инженера; заполнит
`GROUND/config.yaml` и выставит даты свежести. Неинтерактивно — через переменные
`CORTEX_COMPANY`, `CORTEX_PRODUCT`, `CORTEX_SLUG`, `CORTEX_IDEA`, `CORTEX_ENGINEER`.

**3. Запустить в папке Claude Code / Кортекс**

```bash
claude
```

Claude Code подхватывает `CLAUDE.md` → `AGENTS.md` (контракт памяти) и скиллы из
`.claude/skills/`. Агент с первой команды знает правила PAF/ops: источник
обязателен, CP растёт только новым источником, рёбра пишутся полями.

**4. Выполнить онбординг из репозитория**

```
/paf-onboard
```

Интервью по Нексусам в порядке `product → customer → market → growth`, затем
`company` и `team`. На выходе — узлы с источниками и честным CP, а не заполненная
ради полноты база. Порядок шагов — [docs/onboarding.md](docs/onboarding.md).

**5. Получить набор Нексусов, организованной памяти и инструментов**

```bash
./scripts/cortex.sh gate      # схема, рёбра, свежесть — ноль ERROR
./scripts/cortex.sh report    # узлы, рёбра, Context Ripeness по Нексусам
```

Семь Нексусов PAF, типизированные рёбра, метрика спелости контекста и гейт,
не пускающий узел без источника.

**6. Использовать в работе, регулярно обогащая контекст**

| Событие | Команда |
|---|---|
| встреча, созвон, ретро | `/paf-pulse` |
| новый факт, интервью, данные | `/paf-node` |
| цели квартала | `/paf-okr` |
| новый объект управления | `/paf-nexus-create` |
| гейт красный | `/paf-gate` |

**7. Подключить движок памяти** — https://github.com/po-helper-org/poh-memory-engine

```bash
./scripts/cortex.sh engine
./scripts/cortex.sh build     # узлы OKR и PULSE, рёбра в frontmatter
./scripts/cortex.sh gaps      # дыры и достижимость контента от хребта OKR
```

Оцифровка Нексуса: движок выводит рёбра, считает спелость, ловит висячие ссылки
и протухшие узлы — так по памяти можно быстро навигировать.
Детали — [docs/memory-engine.md](docs/memory-engine.md).

**8. Регулярно использовать и развивать Кортекс**

Память живёт, пока её ревизуют: протухший узел верифицируют или понижают ему CP,
дыры закрывают источником, цели квартала обновляют. Чем полнее граф, тем точнее
решения, которые агент способен обосновать, — и тем меньше в них выдумки.

---

## Структура

```
AGENTS.md                    контракт ИИ-агента: правила PAF/ops
CLAUDE.md                    точка входа для Claude Code
VISION.md                    стратегический слой для человека (шаблон)
GROUND/
  config.yaml                организация, продукт, roster ролей, фаза Кортекса
  NEXUS/
    _registry.yaml           реестр Нексусов — источник истины для поля `nexus`
    product/  customer/  market/  growth/     минимальный набор PAF
    company/  team/                           опциональные Нексусы
    ops-model/                                методология: принципы, границы, протокол
    okr/  pulse/  jira/                       генерируются движком
  PULSE/summaries/           эпизоды встреч
  _index/                    очередь кандидатов и статус гейта
ROADMAP/kr-epic-map.md       хребет OKR: KR → эпик
docs/                        методология, схема узла, онбординг, движок
scripts/cortex.sh            init · gate · report · gaps · build · engine
.claude/skills/              скиллы онбординга
```

## Модель

Каждый `.md` с YAML-frontmatter — **Узел**. Рёбра пишутся полями, не текстом,
и выводятся детерминированно.

```
segment —has_need→ need ←addresses— value-proposition ←realizes— feature → product
                                                                    ↓ satisfies
                                                                key-result —serves→ objective
```

Справочник полей и типов — [docs/node-schema.md](docs/node-schema.md).

Правила записи — [`GROUND/NEXUS/ops-model/memory-protocol.md`](GROUND/NEXUS/ops-model/memory-protocol.md).
Коротко: `sources` обязателен (узел без источника = workslop), `confidence`
честный (0.2–0.4 — допущение онбординга), ссылка на несуществующий `node_id`
роняет гейт.

## Гейт

```bash
./scripts/cortex.sh gate
```

Гоняется в CI на каждый push — [`.github/workflows/ground-gate.yml`](.github/workflows/ground-gate.yml).
Проверяет структуру `config.yaml` и реестра, обязательные ключи Node schema,
принадлежность `nexus` реестру, висячие рёбра, дубликаты `node_id`, workslop и
дрейф свежести.

**Свежий клон: 0 ошибок, 6 предупреждений.** Предупреждения — по одному на
ненаполненный Нексус: это ваш список работ онбординга, и он гаснет по мере
заполнения.

## Что здесь сознательно пусто

Шаблон не приносит чужую стратегию. Пустые `VISION.md`, Нексусы и хребет OKR —
не недоделка, а стартовое состояние: онбординг **цифровизует, а не валидирует**,
и правдоподобный текст вместо вашего контекста был бы workslop с первого дня.

Единственный заполненный Нексус — `ops-model`: принципы, граница делегирования
и протокол памяти. Это методология (`kind: normative`), она одинакова для всех.

## Источники и лицензия

Методология: **PAF (Product Ai Framework)**, [productframework.ru/ops/main][S1] и
[productframework.ru/ai_product_roles][S2], Тихомиров С., CC BY-SA 4.0.
Материалы этого репозитория, излагающие PAF, — производные от него.

Движок памяти: [poh-memory-engine](https://github.com/po-helper-org/poh-memory-engine).

[S1]: https://productframework.ru/ops/main
[S2]: https://productframework.ru/ai_product_roles
