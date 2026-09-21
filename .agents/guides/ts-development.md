# BS + TypeScript: локальные front/back-end решения

> Роль BS — «операционный слой» вокруг TS-стека: обнаружение, гейты,
> оркестрация, доставка. Приложение пишетcя на TypeScript; BS его не
> заменяет и не переписывает себя на bash-аналоги сборщиков.

## 1. Что уже реализовано

`lib/ts/toolchain.sh` — модуль обнаружения и гейтов (детали:
`documentation/{en,ru}/03-modules/ts-toolchain.md`):

- `ts::toolchain::detect_runtime / runtimes / runtime_version` — node/bun/deno
  через capability-probe (`utils::has`), без предположений о системе.
- `ts::toolchain::package_managers / lockfile_pm` — pm по лок-файлу проекта
  (pnpm/yarn/bun/npm).
- `ts::toolchain::has_tsconfig / has_node_modules / pkg_field / tsc_bin` —
  инспектура проекта (jq c grep-fallback).
- `ts::toolchain::validate` — гейт `tsc --noEmit` + eslint/prettier (если
  сконфигурированы), вывод `name<TAB>PASS|FAIL|SKIP<TAB>hint` — формат для
  агентов и CI; коды `E_SUCCESS`/`E_ERROR`.
- `ts::toolchain::doctor [dir]` — сводка TS-окружения в стиле `bs doctor`.
- `ts::toolchain::port_free` — цепочка проб `ss → netstat → /dev/tcp`.

Тесты: `tests/unit/testtsunit.sh` (фейковые node/tsc в PATH, без реального
node в CI; хуки `TS_RUNTIMES`, `TS_PACKAGE_MANAGERS`).

## 2. Направления развития (по возрастанию сложности)

### A. `bs ts` — точка входа
Тонкая обёртка над модулем: `bs ts doctor`, `bs ts validate`, `bs ts port-free`.
Плюс проверка tsconfig на «strict-мигрируемость» (grep флагов) — как
`bs doctor` для самого фреймворка.

### B. Стек-оркестратор локальной разработки
`stack up|down|logs|status` — backend (`tsx`/`tsc -w`/`vite preview`) +
frontend (vite) как процессы через `io::process::guard/background`, с
TUI-дашбордом на `lib/tui` (прецедент: `examples/sensor_tui.sh`): статусы
процессов, порты (`port_free`), хвосты логов (`logmonitorexample`), рестарт
по клавише. Деплой на локальный терминал — `bs build` (standalone) +
`system::services` (systemd-юнит) + `network/ssh` для доставки.

### C. Мок-бэкенд и smoke-тесты API
- Мок для фронта: bash-скрипт на listener-цепочке (`socat → ncat`, по
  образцу probe-цепочек `integration/http.sh`), раздаёт JSON-фикстуры из
  каталога; фронт (vite proxy) пишется против него, реальный бэк — позже.
  Совпадает с MVP из `.art/webserver-analysis.md`.
- Смоук против TS-бэкенда: `http::get/post/retry` +
  `dataprocessor::json::query` (jq) — контракты проверяются без Node,
  результат — JSON-контракт `integration/result.sh` для CI.

### D. Связка с железом (сенсор → web)
`sensor::events` (stdout-поток «sec usec type code value») — готовый
production-протокол для TS: Node/Deno читает строки, раздаёт WebSocket в
браузер терминала. BS держит устройство и диагностику, TS — визуализацию.

## 3. Границы

- Bash не обслуживает highload-трафик и не заменяет tsc/eslint/vite — только
  запускает, проверяет, упаковывает.
- Каждая новая возможность — отдельный модуль `lib/ts/*` с тестами и гейтами
  (`bs-validate`), как и всё в репозитории.
- Внешние инструменты — только через probe с деградацией (§11 style-guide).
