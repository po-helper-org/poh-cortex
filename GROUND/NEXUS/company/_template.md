# Шаблон узла — Нексус портфеля организации

Скопируйте блок в начало нового файла `GROUND/NEXUS/company/<node_id>.md`.

```yaml
---
nexus: company
node_id: org-acme
node_type: entity                # entity | concept
paf_step: null
sprint_phase: null
kind: empirical
owner: Portfolio Manager
confidence: 0.4
sources: ["onboarding:doc"]
updated: 2026-01-01
ttl_days: 180
ripeness: fresh
title: ACME — организация
depends_on: []
---
```

## Тело узла

```markdown
# <Заголовок>

Портфель: из чего состоит, кто им владеет, где проходят границы бизнес-юнитов.
Карта систем: где физически живёт то, чем управляем (репозитории, трекеры, БД).

> ⚠️ **допущение (онбординг)**, требует валидации.
```

Опциональный Нексус PAF. Если портфель один и он же продукт — удалите папку
и строку `company` из `_registry.yaml`.
