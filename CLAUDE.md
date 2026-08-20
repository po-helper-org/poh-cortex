# Кортекс организации — правила для Claude Code

Полный контракт: **[AGENTS.md](AGENTS.md)** — прочитайте его перед первой
операцией с памятью. Сценарий развёртывания и работы — QuickStart в
[README](README.md); методология, на которой всё стоит —
[productframework.ru/ops/main](https://productframework.ru/ops/main).
Ниже — то, что нарушается чаще всего.

@AGENTS.md

## Пять правил, без которых не начинать

1. `sources` обязателен. Узел без источника = workslop, он не создаётся.
2. `confidence` растёт только вместе с новым источником, не с рассуждением.
3. Рёбра пишутся полями frontmatter (`realizes`, `addresses`, `has_need`,
   `based_on`, `satisfies`), а не упоминанием в тексте.
4. Ссылка на несуществующий `node_id` роняет гейт. Сначала узел, потом ссылка.
5. Перед коммитом: `./scripts/cortex.sh gate` — ноль ERROR.

## Команды

```bash
./scripts/cortex.sh init      # первичная привязка vault к организации
./scripts/cortex.sh gate      # проверка памяти перед коммитом
./scripts/cortex.sh report    # узлы, рёбра, Context Ripeness
./scripts/cortex.sh gaps      # дыры и достижимость от хребта OKR
./scripts/cortex.sh build     # генерация узлов OKR/PULSE и запись рёбер
```

## Скиллы онбординга

`/paf-onboard` · `/paf-node` · `/paf-nexus-create` · `/paf-okr` · `/paf-pulse` · `/paf-gate`

## Чего не делать

- Не править узлы в `GROUND/NEXUS/okr/` и `GROUND/NEXUS/pulse/` руками:
  их генерирует движок, правки затрутся на следующем `build`.
- Не заполнять пустой раздел правдоподобным текстом ради полноты.
- Не решать за человека цель, приоритет и повышение CP по спорному источнику.
