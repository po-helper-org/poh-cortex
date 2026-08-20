# Шаблон узла — Нексус потребителя

Скопируйте блок в начало нового файла `GROUND/NEXUS/customer/<node_id>.md`.

```yaml
---
nexus: customer
node_id: seg-smb-retail          # seg-... для сегмента, need-... для потребности
node_type: segment               # segment | need
paf_step: 2
sprint_phase: null
kind: empirical
owner: Product Engineer
confidence: 0.3
sources: ["onboarding:interview"]
updated: 2026-01-01
ttl_days: 90
ripeness: fresh
title: Сегмент — розница до 50 точек
has_need: [need-manual-reconciliation]   # только у segment
tags: []                         # [beachhead] — плацдарм, с которого начинаем
---
```

## Тело узла

```markdown
# <Заголовок>

Сегмент: кто это, где обитает, чем отличается от соседнего сегмента.
Потребность: какую работу (JTBD) человек «нанимает» решить и что болит сейчас.

> ⚠️ **допущение (онбординг)**, требует валидации интервью/аналитикой в Steps 1–8.
```

## Правило CP

| Основание | confidence |
|---|---|
| предположение из головы | узел не создавать |
| пересказ внутреннего документа | 0.2–0.4 |
| 3+ проблемных интервью | 0.5–0.7 |
| поведение в данных / эксперимент | 0.8–1.0 |

## Seed questions (PAF)

- Кто основные сегменты?
- Какие работы (JTBD) они «нанимают»?
- Главные боли и их причины?
- Гипотеза монетизируемой ценности (mNSM)?
