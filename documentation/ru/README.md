# Документация BS

**BS** — модульный фреймворк. Его ядро `core/` запускается в любой оболочке из реестра: bash, zsh, dash, busybox ash, ksh, mksh; из fish и nushell — через `bs call`. Реестр оболочек — `bootstrap/shell.sh` (таблица в [shell-portability](08-development/shell-portability.md)).

- **Установить для своей оболочки:** `./install.sh --local --update-path --shell fish` (PATH и подсказки ставятся под эту оболочку).
- **Запустить для определённой оболочки:** `bs --strict-shell=dash КОМАНДА` проверяет, подойдёт ли команда этой оболочке; из fish и nushell функции ядра вызываются так: `bs call ФУНКЦИЯ`.

**Основная библиотека `lib/` пока только для bash 4.2+.** Поэтому BS в целом требует bash 4.2+, а ядро становится независимым от оболочки по шагам: все 15 файлов `core/` уже на POSIX, на bash пока остаются CLI `bootstrap/bs.sh`, установщик.

English version: [documentation/en/](../en/README.md)

## С чего начать

1. [Начало работы](01-getting-started/README.md) — установка, `bs doctor`, `examples/hello.sh`.
2. [Архитектура](02-core-concepts/architecture.md) — как устроена загрузка: `boot.sh` → `bs` → `bootstrap/init.sh` → `loader.sh` → `core/` → `lib/`.
3. [Туториал «Первый скрипт»](05-tutorials/first-script.md) — пошагово: от пустого файла до CLI-утилиты.

## Справочники модулей

- [core/args](03-modules/args.md) — декларативное дерево параметров: валидация, авто-help, completion.
- [core/utils](03-modules/core-utils.md) — идиомы тишины (`utils::has`, `utils::quiet`, `utils::quiet_err`, `utils::ignore`) и служебные хелперы.
- [lib/io/streams](03-modules/io-streams.md) — вывод, ввод, перенаправления, FD, pipe, буферизация.
- [Обзор lib-модулей](03-modules/lib-modules-overview.md) — system, ui, network, data, integration, status, audit и др.
- [Core API](04-api-reference/core-api.md) — `log::*`, `error::*`, `cleanup::*`, коды ошибок, версия.

## Практика

- [Примеры](06-examples/README.md) — все скрипты из `examples/` с командами запуска.
- [Тестирование](07-testing/README.md) — тест-фреймворк, валидаторы, CI-матрица.
- [Установка](install.md) — виды установок (system/local/custom), манифест установки, `bs update` (локальный репозиторий или GitHub), `bs where` (следы BS на машине), PATH-менеджер, uninstall.

## Разработчикам

- [Руководство разработчика](08-development/README.md) — как написать модуль, `# @depends`, проверки перед коммитом.
- [Стиль кода](code-style-guide.md) — соглашения проекта.
- [Лучшие практики](best-practices.md) — высокоуровневые рекомендации для контрибьюторов.
- [Миграция BOSA → BS](09-migration-bosa-to-bs.md) — таблица переименований для тех, кто знал старую версию.
