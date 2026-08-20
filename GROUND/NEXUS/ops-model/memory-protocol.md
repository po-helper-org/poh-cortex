---
nexus: ops-model
node_id: ops-memory-protocol
node_type: operating-model
paf_step: 0
sprint_phase: null
kind: normative
owner: Product Ops
confidence: 1.0
sources: ["repo:poh-memory-engine", "sa_documentation/nexus_schema.md", "sa_documentation/ground_schema.md"]
updated: 2026-08-20
ttl_days: 365
ripeness: fresh
title: Протокол памяти — как писать в этот vault
---

# Протокол памяти

Семь правил. Нарушение любого из них ловится гейтом или превращает память в
документацию, которая гниёт.

1. **Один факт — один узел.** Файл `.md` с YAML-frontmatter по Node schema:
   `nexus`, `node_id`, `node_type`, `kind`, `owner`, `confidence`,
   `sources`, `updated`, `ttl_days`, `ripeness`. Отсутствие ключа = ошибка гейта.

2. **`sources` обязателен.** Пусто = workslop, узел не считается. Источник —
   документ, интервью, аналитика, эксперимент, решение команды. Не «здравый смысл».

3. **Рёбра пишутся полями, не текстом.** `realizes`, `based_on`, `depends_on`,
   `addresses`, `satisfies`, `has_need`, `owner`, `owns_node`, `serves`,
   `reports_to`, `manages`, `collaborates_with`. Движок выводит типизированные
   рёбра детерминированно; связь, упомянутая только в тексте, графом не станет.

4. **Сначала узел, потом ссылка.** Ссылка на несуществующий `node_id` —
   висячее ребро, гейт падает. `node_id` не выдумывается «на будущее».

5. **`confidence` честный.** 0.2–0.4 — допущение онбординга; 0.5–1.0 — после
   валидации. Повышение CP требует **нового источника**, а не нового рассуждения.
   Понижение CP — нормальная операция, а не поражение.

6. **`ripeness` вычисляемый.** `p = (сегодня − updated) / ttl_days`:
   `<0.5` fresh, `<1.0` ripening, `≥1.0` wilting. Wilting-узел **верифицируют
   или понижают CP** — не продлевают дату без проверки. TTL по типу:
   normative 365, product/customer/market 90, growth 60, team 180.

7. **Гейт перед коммитом.** `./scripts/cortex.sh gate` — ноль ERROR.
   WARN про пустой `sources` у `_index` — это список ненаполненных Нексусов,
   он гаснет по мере онбординга.

## Что делать с противоречием

Новый источник противоречит существующему узлу — **не затирать молча**:
обновить узел, указав оба источника, и зафиксировать в теле, что изменилось
и почему. История решений — такой же актив, как текущее состояние.
