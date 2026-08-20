---
nexus: ops-model
node_id: ops-model-index
node_type: spine
paf_step: null
sprint_phase: null
kind: normative
owner: Product Ops
confidence: 1.0
sources: ["[S1]", "[S2]", "repo:poh-memory-engine"]
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Нексус операционной модели
---

# Нексус операционной модели

Правила игры организации. Единственный Нексус, который приезжает из шаблона
**заполненным**: это методология PAF/ops, а не ваш контекст.

- [[principles]] — принципы, по которым принимаются решения
- [[delegation-boundary]] — что владеет система, что владеет человек
- [[memory-protocol]] — как писать в этот vault, чтобы память не сгнила

`kind: normative` означает: CP этих узлов = трассируемость до источников PAF,
а не количество интервью. Меняете методологию под себя — меняйте и `sources`.
