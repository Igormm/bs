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
documentation/      # руководства и справочники / guides and references
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

- `documentation/01-getting-started` — начало работы
- `documentation/03-modules` — обзоры модулей
- `documentation/code-style-guide.md` — стиль кода проекта
- `examples/` — рабочие примеры с комментариями

## Лицензия / License

MIT — см. [LICENSE](LICENSE).
