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
- **Загрузчик модулей** — `load "lib/io/streams"`, зависимости через
  `# @depends`, защита от циклов и повторной загрузки
- **`core/args`** — декларативное дерево параметров: валидация, авто-help,
  флаги `--key value` и генерация bash-completion из одного источника
- **`lib/io/streams`** — безопасный вывод, перенаправления, save/restore FD,
  pipe, буферизация stdio, `/dev` спецфайлы
- **`core/logger`** — уровни, цвета, форматы text/json/structured
- **`core/utils`** — идиомы тишины: `utils::has`, `utils::quiet`,
  `utils::quiet_err`, `utils::ignore` вместо ручных `>/dev/null 2>&1`
- **`lib/integration/*`** — HTTP-клиент, LLM (OpenAI/Ollama), Kubernetes,
  JSON-контракт результата для интеграции с Go-backend / CI
- **`lib/system/*`** — дистрибутивы, пакеты, пользователи, сервисы, сеть,
  устройства (20+ модулей)
- **Тесты и CI** — свой тест-фреймворк, ShellCheck, матрица
  ubuntu / debian / almalinux 8–9 (bash 4.4–5.x)

## Требования / Requirements

- Bash 4.0+
- Linux (основная платформа; macOS — частично)

## Быстрый старт / Quick start

```bash
# Проверка целостности фреймворка / Framework integrity check
./bs doctor

# Список модулей / List modules
./bs list

# Запуск примеров / Run examples
./bs run examples/argsparseexample.sh deploy now --env production --dry-run
./bs run examples/passwordgenexample.sh --length 24 --count 5
./bs run examples/http_example.sh
./bs run examples/llm_example.sh
./bs run examples/k8s_example.sh
```

## Свой скрипт за 5 строк / A script in 5 lines

```bash
#!/usr/bin/env bs
load "core/args"
load "lib/io/streams"

args::define hello
args::parse "$@" || exit 2
io::streams::print "works: $(args::get 1)"
```

Запуск / Run: `./script.sh hello` (с `bs` в PATH) или `bs run script.sh hello`.

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
core/               # const, logger, errorhandler, utils, version, args
lib/                # io, system, ui, network, data, integration, ...
install/            # модульный установщик / modular installer
tests/              # тест-фреймворк и наборы тестов / test framework & suites
examples/           # примеры (bs run examples/...) 
documentation/      # документация: en/ и ru/ (+ archive/) / docs: en/ & ru/ (+ archive/)
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

## Лицензия / License

MIT — см. [LICENSE](LICENSE).
