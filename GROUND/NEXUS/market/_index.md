---
nexus: market
node_id: market-index
node_type: spine
paf_step: 3
sprint_phase: null
kind: empirical
owner: Portfolio Manager
confidence: 0.2
sources: []
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Нексус рынка
---

# Нексус рынка

Объём и динамика рынка, тренды, конкуренты, Ставки (Bets) стратегического сценария.

**Пока пуст.** Наполняется `/paf-onboard` или вручную по `_template.md`.

## Что здесь должно появиться

| Узел | `node_type` | Отвечает на вопрос |
|---|---|---|
| рынок | `concept` | Каков объём рынка и его динамика? |
| конкурент | `entity` | Кто конкуренты и каковы их позиции? |
| Ставка (Bet) | `concept`, `tags: [bet]` | На какой стратегический сценарий ставим? |

> Рыночные цифры без источника — workslop. Нет данных — ставьте `confidence: 0.2`
> и закрывайте скаутингом (Step 3), а не правдоподобным числом.
