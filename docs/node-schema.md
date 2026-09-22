# Справочник: схема узла

Каждый `.md` с YAML-frontmatter — узел. Файл без frontmatter узлом не считается.
Источник истины по схеме — `GROUND/SCHEMA/nodes.yaml`; здесь пояснения к нему.

## Обязательные ключи

| Ключ | Значение |
|---|---|
| `nexus` | только из `GROUND/NEXUS/_registry.yaml` |
| `node_id` | ascii, нижний регистр, **стабильный навсегда**: переименование рвёт рёбра |
| `node_type` | из каталога `SCHEMA/nodes.yaml` или из `node_types` своего Нексуса |
| `kind` | `normative` (методология) · `empirical` (контекст организации) |
| `owner` | роль или имя персоны из Нексуса `team` |
| `sources` | обязателен и непуст: пусто = workslop |
| `updated` | дата последнего осмысленного изменения |
| `ripeness` | вычисляется `cortex refresh`, руками не ставится |

Слой решений (`GROUND/DECIDE/`) живёт по своим обязательным ключам —
`layer_required` в `nodes.yaml`: ставка и артефакт не принадлежат Нексусу.

## Ключи смысла

Не требуются схемой, но именно они делают память пригодной для решения.

| Ключ | Зачем |
|---|---|
| `cp` | ступень 2–9 из `SCHEMA/ladder.yaml` — по сильнейшему артефакту |
| `confidence` | то же в долях (`cp/9`), для отчётов и совместимости |
| `change_rate` | `high` · `medium` · `low` · `unknown`; выводится из истории изменений объекта |
| `ttl_days` | срок годности; если не задан — берётся из `change_rate` |
| `scope` | зона: `org` · `team:<имя>` · `product:<имя>` |
| `captured_by` | кто записал: `human`, `claude-code`, `skill:<имя>`, `hermes:<бот>` |

`change_rate` не угадывается: данных нет ни у вас, ни у владельца — ставится
`unknown`, который трактуется как `high`. Асимметрия ошибки: завысили —
заплатили перепроверкой, занизили — получили протухшее знание и сорванный квартал.

## Рёбра

Пишутся полями, выводятся детерминированно. Полный список —
`GROUND/SCHEMA/edges.yaml`. Ссылка на несуществующий `node_id` роняет гейт.

```
segment —has_need→ need ←addresses— value-proposition ←realizes— feature → product
                                                                    ↓ satisfies
                                                                key-result —serves→ objective
```

Связь, упомянутая только в тексте, графом не становится.

## Расширение схемы

Нужен свой тип узла — объявите его у Нексуса:

```yaml
- {slug: landscape, source: custom, name: IT-ландшафт, scope: org,
   node_types: [system-component, integration], change_rate: high, ...}
```

Нужны свои поля — добавляйте: инструмент не мешает незнакомым ключам и не
теряет их. Обязательные ключи они не заменяют.

## Проверка

```sh
bin/cortex gate
bin/cortex node check <node_id>
```
