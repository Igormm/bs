# Документация BS

**BS** — модульный фреймворк и стандартная библиотека для Bash 4+:
загрузчик модулей, логирование, обработка ошибок, декларативные параметры
скриптов, абстракция потоков ввода/вывода и набор системных модулей.

English version: [documentation/en/](../en/README.md)

## С чего начать

1. [Начало работы](01-getting-started/README.md) — установка, `bs doctor`, первый скрипт за 5 строк.
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
- [Установка](install.md) — режимы system/local, PATH-менеджер, uninstall.

## Разработчикам

- [Руководство разработчика](08-development/README.md) — как написать модуль, `# @depends`, проверки перед коммитом.
- [Стиль кода](code-style-guide.md) — соглашения проекта.
- [Лучшие практики](best-practices.md) — высокоуровневые рекомендации для контрибьюторов.
- [Миграция BOSA → BS](09-migration-bosa-to-bs.md) — таблица переименований для тех, кто знал старую версию.
