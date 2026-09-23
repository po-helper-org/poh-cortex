# Шаблон узла — Нексус системы роста

Скопируйте блок в начало нового файла `GROUND/NEXUS/growth/<node_id>.md`.

```yaml
---
nexus: growth
node_id: growth-partner-channel
node_type: concept
paf_step: 5                       # 5 система роста · 6 питчинг · 8 harvest
sprint_phase: null
kind: empirical
owner: Growth Engineer
cp: 3                             # ступень 2..9 из SCHEMA/ladder.yaml: разговор с владельцем канала; цифры поднимут ступень
change_rate: medium               # как часто объект менялся: high | medium | low | unknown
# confidence инструмент ставит сам (cp/9) — руками его не пишут
sources: ["onboarding:interview"]
updated: 2026-01-01
ttl_days: 60                      # выводится из change_rate по SCHEMA/profiles.yaml
ripeness: fresh
title: Канал — <название канала>
based_on: []                      # на каком узле продукта держится
---
```

## Тело узла

```markdown
# <Заголовок>

Как ценность превращается в деньги: канал, юнит-экономика, рычаг роста NPV.

**Рычаг (Lever):** <какое измеримое свойство растёт при инвестиции>

> ⚠️ **допущение (онбординг)**, требует валидации в Steps 1–8.
```

## Seed questions (PAF)

- Каковы каналы дистрибуции и роста?
- Какова модель монетизации?
- Каков AI-COGS (затраты ИИ в стоимости)?
- Какие рычаги (Lever) дают рост NPV?
