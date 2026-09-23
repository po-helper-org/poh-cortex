---
nexus: customer
node_id: customer-index
node_type: spine
paf_step: 2
sprint_phase: null
kind: empirical
owner: Product Engineer
scope: org
captured_by: human
confidence: 0.2
sources: []
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Нексус потребителя
---

# Нексус потребителя

Сегменты, их работы (JTBD), боли и гипотеза монетизируемой ценности (mNSM).

**Пока пуст.** Наполняется `/paf-onboard` или вручную по `_template.md`.

## Что здесь должно появиться

| Узел | `node_type` | Отвечает на вопрос |
|---|---|---|
| сегмент | `segment` | Кто основные сегменты? |
| потребность | `need` | Какие работы (JTBD) они «нанимают» и какие боли за этим стоят? |

Сегмент связывается с потребностями полем `has_need: [need-...]`.

> Сегмент, описанный без единого интервью, живёт с `confidence` 0.2–0.4.
> Поднять CP можно только новым источником, не рассуждением.
