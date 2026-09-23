---
nexus: product
node_id: product-index
node_type: spine
paf_step: 1
sprint_phase: null
kind: empirical
owner: Product Engineer
scope: org
captured_by: human
sources: []
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Нексус продукта
---

# Нексус продукта

Цифровой профиль продукта: идея, фичи, Видение, гэп между текущим продуктом и Видением.

**Пока пуст.** Наполняется `/paf-onboard` или вручную по `_template.md`.

## Что здесь должно появиться

| Узел | `node_type` | Отвечает на вопрос |
|---|---|---|
| продукт | `product` | В чём идея продукта? |
| ценностное предложение | `value-proposition` | Какую боль сегмента закрываем? |
| фича | `feature` | Какой кирпичик ценности реализует предложение? |

## Ось ценности

`segment` —`has_need`→ `need` ←`addresses`— `value-proposition` ←`realizes`— `feature` → `product`

Узел продукта, не привязанный к этой цепочке, недостижим от хребта OKR —
`paf_index gaps` покажет его сиротой.
