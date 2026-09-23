# Шаблон узла — Нексус продукта

Скопируйте блок в начало нового файла `GROUND/NEXUS/product/<node_id>.md`.
Этот файл движок игнорирует (имя `_template.md`), поэтому фантомных узлов не создаёт.

```yaml
---
nexus: product
node_id: f-billing-export         # ascii, нижний регистр, стабильный навсегда
node_type: feature                # product | value-proposition | feature | interface | platform | service
paf_step: 1                       # 1 идея · 4 фичи/банч · 7 исполнение
sprint_phase: null
kind: empirical
owner: Product Engineer
cp: 3                             # ступень 2..9 из SCHEMA/ladder.yaml: решение встречи; прогон против системы поднимет ступень
change_rate: medium               # как часто объект менялся: high | medium | low | unknown
# confidence инструмент ставит сам (cp/9) — руками его не пишут
sources: ["onboarding:interview"] # ОБЯЗАТЕЛЬНО. Пусто = workslop
updated: 2026-01-01
ttl_days: 90                      # выводится из change_rate по SCHEMA/profiles.yaml
ripeness: fresh
title: Выгрузка счетов в 1С
realizes: []                      # feature → value-proposition
addresses: []                     # value-proposition → need
depends_on: []                    # product → feature
satisfies: []                     # → key-result, появляется после /paf-okr
---
```

## Тело узла

```markdown
# <Заголовок>

Один факт — один узел. 3–8 строк: что это, для кого, чем измеряется эффект.

**Метрика эффекта:** <что меняется в цифрах, если узел верен>

> ⚠️ **допущение (онбординг)**, требует валидации в Steps 1–8.
> CP отражает уровень доверия к допущению, не подтверждённый факт.
```

## Ось ценности

`segment` —`has_need`→ `need` ←`addresses`— `value-proposition` ←`realizes`— `feature` → `product`

Фича без `realizes` — сирота: она ничего не реализует и не видна от хребта OKR.

## Seed questions (PAF)

- В чём идея продукта?
- Какие фичи закрывают гэп до Видения?
- Каково Видение — образ продукта, нужный рынку и компании?
- Каков гэп между текущим продуктом и Видением?
