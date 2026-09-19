# BS Framework

**BS** — модульный фреймворк и стандартная библиотека для Bash 4+:
загрузчик модулей, логирование, обработка ошибок, декларативные параметры
скриптов, абстракция потоков ввода/вывода и набор системных модулей —
всё в едином code style и без единой внешней зависимости.

**BS** is a modular framework and standard library for Bash 4+:
a module loader, logging, error handling, declarative script parameters,
an I/O streams abstraction and a set of system modules — all in a
consistent code style and with zero external dependencies.

## Возможности / Features

- **Интерпретатор `bs`** — shebang-режим (`#!/usr/bin/env bs`) и `bs run`:
  скрипты не требуют bootstrap-бойлерплейта
- **Интерактивный REPL `bs repl`** — сессия с загруженным ядром: `load`,
  eval-выражения, история команд, интроспекция (`:list`, `:doc`, `:info`)
- **Standalone-сборка `bs build`** — превращает скрипт в один
  самодостаточный файл (фреймворк внутри, извлекается в кэш при первом
  запуске): работает в любом дистрибутиве без установки BS
- **`bs update`** — применить изменения репозитория к установленным копиям
  без переустановки (local/system/custom): `./bs update --local`
- **Загрузчик модулей** — `load "lib/io/streams"`, зависимости через
  `# @depends`, защита от циклов и повторной загрузки
- **`core/args`** — декларативное дерево параметров: валидация, авто-help,
  флаги `--key value`, дефолты, типы значений (`number`, `enum:a,b`,
  валидатор-колбэк), повторяемые уровни, `--` для сырых аргументов и
  генерация bash-completion из одного источника
- **`lib/io/streams`** — безопасный вывод, перенаправления, save/restore FD,
  pipe, буферизация stdio, `/dev` спецфайлы
- **`core/logger`** — уровни, цвета, форматы text/json/structured
- **`core/utils`** — идиомы тишины: `utils::has`, `utils::quiet`,
  `utils::quiet_err`, `utils::ignore`, `utils::attempt` вместо ручных
  `>/dev/null 2>&1`
- **`core/lang`** — языковое ядро: предикаты `is::file`, `is::empty`,
  `is::command`, строки `str::*`, коллекции `arr::*`/`map::*`, интроспекция
  `bs::func_name` и `bs::type_of`
- **`lib/tui`** — чистый bash TUI: diff-рендер, клавиши/мышь, модалки
- **`lib/platform/facts`** — вектор возможностей (пробы, не `uname`)
- **`lib/rfc/*`** — UUID (RFC 4122/9562), URI, CSV
- **`lib/integration/*`** — HTTP-клиент, LLM (OpenAI/Ollama), Kubernetes,
  JSON-контракт результата для интеграции с Go-backend / CI
- **`lib/system/*`** — дистрибутивы, пакеты, пользователи, сервисы, сеть,
  устройства, hw (20+ модулей)
- **Тесты и CI** — свой тест-фреймворк, ShellCheck, матрица
  ubuntu / debian / almalinux 8–9 (bash 4.4–5.x)

## Требования / Requirements

- Bash 4.4+ (CI-минимум; Bash 4.0–4.3 не проверяется)
- Linux (основная платформа; macOS — частично)

## Быстрый старт / Quick start

```bash
# Проверка целостности фреймворка / Framework integrity check
./bs doctor

# Интерактивная консоль / Interactive shell
./bs repl

# Список модулей / List modules
./bs list

# Три примера со стартовой / Three landing examples
./bs run examples/hello.sh
./bs run examples/todo.sh
./bs run examples/pulse.sh
```

## 1. Короткий скрипт / A short script

`examples/hello.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
set -euo pipefail

load "lib/io/streams"

io::streams::print "hello from BS ${BS_VERSION}"
```

Запуск / Run: `./bs run examples/hello.sh`

## 2. TUI todo list

Чистый bash, `lib/tui`: список, модалки ввода/подтверждения, файл `~/.todo.tsv`.

```bash
./bs run examples/todo.sh
./bs run examples/todo.sh --file /tmp/tasks.tsv
```

Клавиши / Keys: `↑↓` выбор, `Enter` toggle, `a` add, `e` edit, `d` delete, `q` выход.

## 3. Пульс машины / Host pulse

Вектор возможностей: тир, userland, пробы `grep -P`/`sed -z`, SHA-цепочка,
железо если есть `/proc`. Не `uname`-ветвление.

```bash
./bs run examples/pulse.sh
```

## Установка / Installation

BS можно запускать прямо из клонированного репозитория, но для регулярного
использования удобно установить команду `bs` в `PATH`.

```bash
# Локальная установка в ~/.local (без sudo)
./install.sh --local

# Системная установка в /usr/local (нужен root)
sudo ./install.sh
```

Установщик **копирует** файлы фреймворка в целевой каталог и создаёт
обёртку `bs` в соответствующем `bin/`. После успешной установки исходный
репозиторий можно удалить — BS будет работать из целевого каталога.

### Один файл без установки / A single file without installation

```bash
# Собрать самодостаточный исполняемый файл (фреймворк внутри, ~230 КБ)
./bs build examples/sysdiag.sh                 # → examples/sysdiag.standalone.sh

# Запуск на любой машине с bash 4+ (дистрибутив не важен)
./examples/sysdiag.standalone.sh quick
```

При первом запуске встроенный фреймворк распаковывается в кэш
`$XDG_CACHE_HOME/bs/<hash>` (переопределяется `BS_BUILD_CACHE_DIR`).
Дистрибутив-агностично: не требует установки BS и root-прав.

| Режим | Куда копируется | Обёртка |
|-------|-----------------|---------|
| `--local` | `~/.local/lib/bs` | `~/.local/bin/bs` |
| system (по умолчанию) | `/usr/local/lib/bs` | `/usr/local/bin/bs` |
| custom | `$LIB_DIR/bs` | `$BIN_DIR/bs` |

Пути переопределяются переменными окружения `PREFIX`, `BIN_DIR` и
`LIB_DIR`. Подробнее — в [documentation/ru/install.md](documentation/ru/install.md)
/ [documentation/en/install.md](documentation/en/install.md).

## Структура / Layout

```
bs                  # stage-2: CLI и shebang-интерпретатор / CLI & interpreter
boot.sh             # stage-1: проверка среды и поиск BS_ROOT
bootstrap/          # init.sh, загрузчик модулей loader.sh
core/               # prereq, lang, const, logger, errorhandler, utils,
                    # version, config, deps; args и repl — по запросу
lib/                # io, tui, system, ui, network, data, platform, rfc,
                    # integration, ...
install/            # модульный установщик / modular installer
tests/              # тест-фреймворк и наборы тестов / test framework & suites
examples/           # примеры (bs run examples/...)
documentation/      # документация: en/ и ru/ / docs: en/ & ru/
AGENTS.md           # контракт для ИИ / AI agent contract
```

## Тестирование / Testing

```bash
bash tests/runalltests.sh          # весь набор / full suite
bash tests/validatesyntax.sh       # синтаксис bash / bash syntax
bash tests/validateshellcheck.sh   # ShellCheck (уровень error)
```

CI (GitHub Actions): lint + матрица тестов в контейнерах
ubuntu, debian:stable, almalinux:9, almalinux:8 — см. `.github/workflows/ci.yml`.

## Документация / Documentation

Полная документация на двух языках / Full documentation in two languages:

- **[documentation/ru/](documentation/ru/README.md)** — русская документация
- **[documentation/en/](documentation/en/README.md)** — English documentation

Точки входа / Entry points:

- Начало работы / Getting started — [ru](documentation/ru/01-getting-started/README.md) · [en](documentation/en/01-getting-started/README.md)
- Архитектура / Architecture — [ru](documentation/ru/02-core-concepts/architecture.md) · [en](documentation/en/02-core-concepts/architecture.md)
- Идиомы тишины `utils::quiet*` / Silence idioms — [ru](documentation/ru/03-modules/core-utils.md) · [en](documentation/en/03-modules/core-utils.md)
- JSON-контракт результата / Result contract — [ru](documentation/ru/03-modules/integration-result.md) · [en](documentation/en/03-modules/integration-result.md)
- HTTP, LLM, Kubernetes / HTTP, LLM, Kubernetes — [ru](documentation/ru/03-modules/integration-http.md) · [en](documentation/en/03-modules/integration-http.md)
- Стиль кода / Code style — [ru](documentation/ru/code-style-guide.md) · [en](documentation/en/code-style-guide.md)
- `examples/` — рабочие примеры с комментариями / working examples with comments

## Ценности / Values

- **Вездесущность** — Bash 4+ есть везде: ноль установки, ноль внешних
  зависимостей в рантайме. / **Ubiquity** — Bash 4+ ships everywhere:
  zero install, zero external runtime dependencies.
- **Совместимость важнее новизны** — BS это bash + конвенции, а не новый
  язык: вся экосистема bash открыта. / **Compatibility over novelty** —
  BS is bash plus conventions, not a new language: the whole bash
  ecosystem stays open.
- **Прозрачность** — каждая строка читаемый bash: `bash -x`, `declare -p`,
  никакой магии. / **Transparency** — every line is readable bash, no magic.
- **Ноль форков в ядре** — языковые примитивы — чистый bash, без внешних
  команд. / **Zero forks in the core** — language primitives are pure bash.
- **Операционность** — cron, CI, Docker, матрица дистрибутивов (bash 4.4–5.x),
  `bs build` в один самодостаточный файл. / **Ops-first** — cron, CI,
  Docker, distro matrix, standalone builds.
- **Честные границы** — BS не язык с типами и замыканиями; данные
  делегируются бинарникам (jq, Go) по JSON-контракту. / **Honest
  boundaries** — data-heavy work goes to binaries (jq, Go) via a JSON
  contract.

Чем платим / What we pay: префиксы `__arr_*` вместо namespace, колбэки
по имени вместо замыканий, дисциплина вместо компилятора, рантайм-
проверки вместо статических гарантий.

## Лицензия / License

MIT — см. [LICENSE](LICENSE).
