# Шаблон узла — Нексус организационной структуры (People Graph)

Скопируйте блок в начало нового файла `GROUND/NEXUS/team/team-<фамилия-имя>.md`.

```yaml
---
nexus: team
node_id: team-ivanov-ivan
node_type: person
paf_step: null
sprint_phase: null
kind: empirical
owner: Product Ops
cp: 3                             # ступень 2..9 из SCHEMA/ladder.yaml: засеяно из оргструктуры, связи не подтверждены
change_rate: medium               # как часто объект менялся: high | medium | low | unknown
# confidence инструмент ставит сам (cp/9) — руками его не пишут
sources: ["config.yaml:roster"]   # или onboarding:interview, hr-system, self-reported
updated: 2026-01-01
ttl_days: 180                     # выводится из change_rate по SCHEMA/profiles.yaml
ripeness: fresh
title: Иван Иванов — Product Manager
full_name: Иванов Иван Иванович
role_title: Product Manager
department: Продукт
reports_to: null                  # node_id руководителя
manages: []
collaborates_with: []
influence_zones: ["роадмап продукта", "приоритизация фич"]
expertise_topics: ["product discovery", "JTBD", "A/B тесты"]
contact_for: ["приоритет фичи", "статус релиза"]
context_holds: Знает историю решений по онбордингу за два года
---
```

## Тело узла

```markdown
# <Имя>

**Зоны ответственности:** <что решает>
**Делегировано Кортексу:** <что закрывает ИИ-агент>
```

## Правила

- Связи не выдумывать: пустое поле честнее выдуманной иерархии, а ссылка на
  несуществующий `node_id` роняет гейт.
- `roster` в `config.yaml` — источник истины по ролям; здесь — богатый профиль.
- Публичный репозиторий: держите People Graph по ролям и рабочим контактам,
  личные данные — в приватном форке.

## Seed questions (PAF)

- Полное имя и должность каждого ключевого человека?
- Какие зоны ответственности и принятия решений у каждого?
- Кто кому подчиняется, кто с кем взаимодействует помимо иерархии?
- По каким вопросам к кому обращаться?
