[↑ Указатель документации](../README.md)

# Модуль `ts::toolchain`

Обнаружение и верификационные гейты инструментария TypeScript: рантаймы
(node/bun/deno), пакетные менеджеры (по лок-файлу), инспектура
`tsconfig`/`node_modules`, гейт `tsc`/`eslint`/`prettier` с машиночитаемым
выводом, диагностика окружения и проверка портов. Только пробы — ничего не
предполагается, при недоступности — чистая деградация с кодами `LIB_ERROR_*`.

Источник: [lib/ts/toolchain.sh](../../../lib/ts/toolchain.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/ts/toolchain"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `TS_RUNTIMES` | `node bun deno` | порядок проб рантаймов |
| `TS_PACKAGE_MANAGERS` | `npm pnpm yarn bun` | порядок проб пакетных менеджеров |

## Рантаймы и пакетные менеджеры

```bash
ts::toolchain::detect_runtime          # первый доступный: "node"
ts::toolchain::runtime_version node    # "22.1.2" (без префикса v)
ts::toolchain::runtimes                # строки "bin<TAB>версия<TAB>путь"
ts::toolchain::package_managers        # тот же формат
ts::toolchain::lockfile_pm ./proj      # pnpm|yarn|bun|npm по лок-файлу
```

## Структура проекта

```bash
ts::toolchain::has_tsconfig ./proj     # предикат 0/1
ts::toolchain::has_node_modules ./proj # предикат 0/1
ts::toolchain::tsc_bin ./proj          # node_modules/.bin/tsc, затем глобальный
ts::toolchain::pkg_field ./proj version # поле package.json (jq, fallback grep)
```

## Гейт валидации

```bash
ts::toolchain::validate ./proj
# tsc	PASS
# eslint	SKIP	no config or binary
# prettier	SKIP	no config or binary
```

Формат: `имя<TAB>PASS|FAIL|SKIP<TAB>подсказка`; `FAIL` несёт первую строку
ошибки. Код возврата — `E_SUCCESS`, если `FAIL` нет.

## Диагностика и порты

```bash
ts::toolchain::doctor ./proj      # сводка окружения в стиле bs doctor
ts::toolchain::port_free 5173     # ss → netstat → /dev/tcp (0 — свободен)
```

## Связанное

- `.agents/guides/ts-development.md` — BS как операционный слой TS-разработки.
- `lib/integration/http.sh` + `lib/data/dataprocessor.sh` — smoke-тесты API.
