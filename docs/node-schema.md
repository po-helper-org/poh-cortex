# Справочник: Node schema

Каждый `.md` в `GROUND/NEXUS/**` с YAML-frontmatter — узел графа.
Файл без frontmatter узлом не считается и гейтом игнорируется.

## Обязательные ключи

| Ключ | Тип | Значение |
|---|---|---|
| `nexus` | slug | **только** из `GROUND/NEXUS/_registry.yaml` |
| `node_id` | ascii-строка | стабильный навсегда; переименование рвёт рёбра |
| `node_type` | enum | см. ниже |
| `kind` | enum | `normative` (методология) · `empirical` (контекст организации) |
| `owner` | строка | роль PAF или имя персоны из Нексуса `team` |
| `confidence` | 0..1 | Confidence Point |
| `sources` | список | обязателен и непуст; пусто = workslop |
| `updated` | YYYY-MM-DD | дата последнего осмысленного изменения |
| `ttl_days` | int | срок годности |
| `ripeness` | enum | `fresh` · `ripening` · `wilting` — вычисляемое |

Необязательные: `paf_step` (0–8 или null), `sprint_phase`, `tags`, `title`.

## `node_type`

| Группа | Значения |
|---|---|
| каркас | `spine`, `operating-model`, `gates`, `bootstrap`, `step-overview`, `sprint-phase` |
| ось ценности | `product`, `service`, `interface`, `platform`, `feature`, `value-proposition`, `need`, `segment` |
| хребет OKR | `objective`, `key-result`, `epic`, `task` |
| прочее | `person`, `episode`, `risk`, `decision`, `component-ref`, `entity`, `concept` |

## Рёбра

Пишутся полями, выводятся детерминированно. Ссылка на несуществующий `node_id`
роняет гейт.

| Поле | Ребро | Направление |
|---|---|---|
| `has_need` | HAS_NEED | segment → need |
| `addresses` | ADDRESSES | value-proposition → need |
| `realizes` | REALIZES | feature → value-proposition |
| `depends_on` | DEPENDS_ON | product → feature |
| `based_on` | BASED_ON | узел → основание |
| `satisfies` | SATISFIES | узел → key-result |
| `serves` | SERVES | key-result → objective |
| `owner`, `owns_node` | OWNS | персона → узел |
| `reports_to`, `manages` | org chart | person → person |
| `collaborates_with` | social graph | person → person |
| `mentions`, `involves` | из эпизодов PULSE | генерируются движком |

**Ось ценности:**

```
segment —has_need→ need ←addresses— value-proposition ←realizes— feature → product
                                                                    ↓ satisfies
                                                                key-result —serves→ objective
```

## TTL по типам

| Что | `ttl_days` |
|---|---|
| методология (`normative`) | 365 |
| продукт, потребитель, рынок | 90 |
| система роста | 60 |
| персоны (`team`) | 180 |
| портфель (`company`) | 180 |

## Файлы, которые движок пропускает

| Имя | Поведение |
|---|---|
| `_template.md` | пропускается линтером; **не давайте ему настоящий frontmatter** — загрузчик узлов читает любой файл с `node_id` и создаст фантом |
| `_index.md`, `_registry.yaml` | пустой `sources` — WARN, а не ERROR |
| файлы без frontmatter | не узлы, игнорируются |
| `GROUND/PULSE/summaries/*.md` | формат эпизода, не Node schema; гейт их не линтует |

## Проверка

```bash
./scripts/cortex.sh gate
```
