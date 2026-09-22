[↑ Оглавление](../README.md)

# Модуль `ts::stack`

Оркестратор локального мини-стека TypeScript. Имя по умолчанию: **thriller**.
BS поднимает процессы и помнит pid/порты; приложение остаётся на TS
(или статический мок на Python, если Node нет).

Исходник: [lib/ts/stack.sh](../../../lib/ts/stack.sh)

## CLI

```bash
bs ts init ./app
bs ts up ./app
bs ts status
bs ts logs api
bs ts down
```

Переопределения: `TS_STACK_NAME`, `TS_STACK_STATE`, `TS_STACK_API_CMD`,
`TS_STACK_WEB_CMD`, `TS_STACK_API_PORT`, `TS_STACK_WEB_PORT`.

Без Node: `init` пишет `fixtures/`, `up` раздаёт их через
`python3 -m http.server`, если он есть. С `tsx`/`node` API —
`apps/api/index.ts`.

## См. также

- [ts-toolchain.md](ts-toolchain.md) — doctor, validate, port_free
- `.agents/guides/ts-development.md` — роли (BS = ops, TS = приложение)
