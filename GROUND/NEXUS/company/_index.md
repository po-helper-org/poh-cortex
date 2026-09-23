---
nexus: company
node_id: company-index
node_type: spine
paf_step: null
sprint_phase: null
kind: empirical
owner: Portfolio Manager
scope: org
captured_by: human
sources: []
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Нексус портфеля организации
---

# Нексус портфеля организации

Портфель продуктов и бизнес-юнитов (Business Pod), карта систем и репозиториев,
скаутинг возможностей и угроз на уровне компании.

**Пока пуст.** Наполняется `/paf-onboard` или вручную по `_template.md`.

## Что здесь должно появиться

| Узел | `node_type` | Отвечает на вопрос |
|---|---|---|
| организация / бизнес-юнит | `entity` | Из чего состоит портфель? |
| карта систем | `concept` | Где физически живёт то, чем мы управляем? |

Опциональный Нексус PAF: если портфель один и он же продукт — удалите папку
и строку `company` из `_registry.yaml`.
