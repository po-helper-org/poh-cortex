---
nexus: team
node_id: team-index
node_type: spine
paf_step: null
sprint_phase: null
kind: empirical
owner: Product Ops
scope: org
captured_by: human
confidence: 0.2
sources: []
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Нексус организационной структуры
---

# Нексус организационной структуры

People Graph: один человек — один узел (`node_type: person`). Даёт ИИ-агенту
навигацию «кто чем владеет, к кому идти с вопросом, кто с кем связан».

**Пока пуст.** Наполняется `/paf-onboard` или вручную по `_template.md`.

## Три слоя графа

| Слой | Поля | Что даёт |
|---|---|---|
| org chart | `reports_to`, `manages` | иерархия и зона решения |
| social graph | `collaborates_with` | реальные рабочие связи мимо иерархии |
| expertise graph | `expertise_topics`, `contact_for` | роутинг вопроса к нужному человеку |

> Персональные данные: в публичном репозитории держите People Graph по ролям
> и рабочим контактам. Личное — в приватном форке.
