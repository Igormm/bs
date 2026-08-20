# Туториал: первый скрипт

[↑ Оглавление](../README.md)

Цель: от пустого файла собрать небольшую CLI-утилиту `deploy-lite.sh` с:

- объявленными и валидируемыми аргументами ([core/args.sh](../../../core/args.sh));
- цветным выводом через логгер (загружается автоматически точкой входа `bs`);
- форматированным выводом статуса ([lib/io/streams.sh](../../../lib/io/streams.sh));
- обработкой ошибок с кодами возврата.

Все команды ниже запускаются из корня репозитория через `./bs run`. Каждый блок вывода в этом туториале получен реальным запуском скрипта.

## Шаг 1: Минимальный скрипт

Создайте `deploy-lite.sh`:

```bash
#!/usr/bin/env bs
log::info "Hello from BS"
```

Shebang `#!/usr/bin/env bs` позволяет запускать скрипт напрямую в окружении BS (требуется `bs` в `PATH`). Из корня репозитория скрипт всегда можно запустить без установки:

```bash
./bs run deploy-lite.sh
```

Вывод:

```text
[2026-07-29 22:27:23] INFO  Hello from BS
```

Логгер — часть ядра и уже загружен: для `log::info`, `log::warn`, `log::error`, `log::success` вызов `load` не нужен. В терминале названия уровней подсвечены цветом; в pipe вывод идёт без цвета.

## Шаг 2: Объявление параметров

Подключите модуль `core/args` и объявите, что принимает утилита: две позиционные команды на уровне 1 и два флага.

```bash
#!/usr/bin/env bs

load "core/args"

main() {
    args::level 1 deploy status
    args::flag env value
    args::flag dry-run

    args::describe deploy "Deploy the application"
    args::describe status "Show environment status"
    args::flag_describe env "Target environment: staging or production (default: staging)"
    args::flag_describe dry-run "Print the plan without executing"
}

main "$@"
```

- `args::level 1 deploy status` — на уровне 1 допустим `deploy` **или** `status` (ветвление дерева).
- `args::flag env value` — флаг со значением (`--env production` или `--env=production`).
- `args::flag dry-run` — булев флаг без значения.
- Флаги не занимают позиционные уровни: `deploy --dry-run` и `--dry-run deploy` эквивалентны.
- `args::describe` / `args::flag_describe` наполняют текст help. Валидация и help используют один источник данных, поэтому не могут разойтись.

Скрипт пока ничего нового не печатает — дерево объявлено, но не используется.

## Шаг 3: Валидация и автоматический help

Добавьте `args::parse` после объявлений:

```bash
    args::parse "$@" || bs::exit "${E_INVALID}"
    [[ "${ARGS_HELP_REQUESTED}" == "1" ]] && bs::exit "${E_SUCCESS}"
```

- При любом неверном вводе `args::parse` сам печатает причину и help в stderr и возвращает `E_INVALID` — мы выходим с этим кодом через `bs::exit`, который выполняет стек очистки.
- `-h`/`--help` печатает help, выставляет `ARGS_HELP_REQUESTED=1` и возвращает 0.
- `E_SUCCESS`, `E_ERROR`, `E_INVALID` (0/1/2) — константы из [core/const.sh](../../../core/const.sh), загружаемые точкой входа BS.

Запуск:

```bash
./bs run deploy-lite.sh --help
```

Вывод:

```text
Usage: bash [flags] [deploy|status]

Parameters / Параметры:
  level 1: deploy | status
    deploy           — Deploy the application
    status           — Show environment status

Flags / Флаги:
    --dry-run              — Print the plan without executing
    --env <value>          — Target environment: staging or production (default: staging)
    --help                 — Show this help and exit
```

Примечание: `args::help` по умолчанию берёт basename `$0`, а под `bs run` `$0` — это `bash`. Чтобы напечатать фиксированное имя программы, вызовите `args::help "deploy-lite.sh"` явно (см. [examples/argsparseexample.sh](../../../examples/argsparseexample.sh)).

## Шаг 4: Провалидированные значения и обработка ошибок

После успешного `args::parse` позиционные параметры лежат в массиве `ARGS_PARAMS`, а значения флагов читаются через `args::flag_get`:

```bash
    local action="${ARGS_PARAMS[0]:-status}"
    local env
    env="$(args::flag_get env || printf 'staging')"

    case "${env}" in
        staging|production) ;;
        *)
            log::error "Unknown environment: ${env} (expected staging or production)"
            bs::exit "${E_ERROR}"
            ;;
    esac

    if args::flag_get dry-run >/dev/null; then
        log::warn "DRY RUN: no changes will be made"
    fi
```

- `args::flag_get` печатает значение флага и возвращает 1, если флаг не задан, поэтому `|| printf 'staging'` задаёт значение по умолчанию.
- Уровень аргументов проверяет *синтаксис* (неизвестные имена, неверные уровни). *Семантические* проверки вроде «существуют только staging/production» остаются в скрипте: сообщайте о них через `log::error` и выходите с `E_ERROR`.
- `log::error` пишет в stderr, поэтому ошибки не попадают в stdout-конвейеры.

Запуск:

```bash
./bs run deploy-lite.sh deploy --env production --dry-run
```

Вывод:

```text
[2026-07-29 22:26:59] WARN  DRY RUN: no changes will be made
[2026-07-29 22:26:59] INFO  Deploying to production...
  artifacts  resolved
  release    applied
  health     green
[2026-07-29 22:26:59] SUCCESS Deploy to production finished
```

И семантическая ошибка:

```bash
./bs run deploy-lite.sh deploy --env mars
```

Вывод (stderr) и код возврата:

```text
[2026-07-29 22:26:59] ERROR Unknown environment: mars (expected staging or production)
```

```text
exit=1
```

## Шаг 5: Форматированный вывод через io::streams

Для машиночитаемых строк статуса используйте `io::streams::printf` — строка формата передаётся отдельным аргументом, поэтому данные никогда не попадают в format string:

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"

# ... inside main(), the status branch:
        status)
            io::streams::printf '  %-11s %s\n' "environment" "${env}" "release" "v1.0.0" "health" "green"
            ;;
```

Запуск:

```bash
./bs run deploy-lite.sh status
```

Вывод:

```text
  environment staging
  release     v1.0.0
  health      green
```

`io::streams` также предоставляет `io::streams::print` (безопасная замена `echo`), `io::streams::eprint` (stderr) и средства перенаправлений (`redirect_all`, `save`/`restore`) — см. [lib/io/streams.sh](../../../lib/io/streams.sh) и [examples/deploytoolexample.sh](../../../examples/deploytoolexample.sh).

## Финальный скрипт

```bash
#!/usr/bin/env bs
# deploy-lite.sh — tiny deploy CLI: args + colored output + error handling

load "core/args"
load "lib/io/streams"

main() {
    # 1. Declare the parameter tree and flags
    args::level 1 deploy status
    args::flag env value
    args::flag dry-run

    args::describe deploy "Deploy the application"
    args::describe status "Show environment status"
    args::flag_describe env "Target environment: staging or production (default: staging)"
    args::flag_describe dry-run "Print the plan without executing"

    # 2. Validate input; on error parse prints the reason and help itself
    args::parse "$@" || bs::exit "${E_INVALID}"
    [[ "${ARGS_HELP_REQUESTED}" == "1" ]] && bs::exit "${E_SUCCESS}"

    # 3. Work with validated values
    local action="${ARGS_PARAMS[0]:-status}"
    local env
    env="$(args::flag_get env || printf 'staging')"

    # Runtime validation: only two environments exist
    case "${env}" in
        staging|production) ;;
        *)
            log::error "Unknown environment: ${env} (expected staging or production)"
            bs::exit "${E_ERROR}"
            ;;
    esac

    if args::flag_get dry-run >/dev/null; then
        log::warn "DRY RUN: no changes will be made"
    fi

    case "${action}" in
        deploy)
            log::info "Deploying to ${env}..."
            io::streams::printf '  %-10s %s\n' "artifacts" "resolved" "release" "applied" "health" "green"
            log::success "Deploy to ${env} finished"
            ;;
        status)
            io::streams::printf '  %-11s %s\n' "environment" "${env}" "release" "v1.0.0" "health" "green"
            ;;
    esac
}

main "$@"
```

Проверьте путь ошибки валидации:

```bash
./bs run deploy-lite.sh fly
```

Вывод (stderr) и код возврата:

```text
ERROR: unknown parameter: "fly"
Usage: bash [flags] [deploy|status]

Parameters / Параметры:
  level 1: deploy | status
    deploy           — Deploy the application
    status           — Show environment status

Flags / Флаги:
    --dry-run              — Print the plan without executing
    --env <value>          — Target environment: staging or production (default: staging)
    --help                 — Show this help and exit
```

```text
exit=2
```

Контракт кодов возврата утилиты: `0` (`E_SUCCESS`) — успех, `1` (`E_ERROR`) — ошибка выполнения, `2` (`E_INVALID`) — неверные аргументы.

## Примечания

- Предпочитайте идиомы BS голым перенаправлениям ([core/utils.sh](../../../core/utils.sh)): `utils::has cmd` вместо `command -v cmd >/dev/null 2>&1`, `utils::quiet cmd` вместо `cmd >/dev/null 2>&1`, `utils::quiet_err cmd` вместо `cmd 2>/dev/null`, `utils::ignore cmd` вместо `cmd >/dev/null 2>&1 || true`.
- Чтобы запускать скрипт как `./deploy-lite.sh`, `bs` должен быть в `PATH` (shebang-режим); иначе используйте `bs run`.
- Из того же дерева параметров бесплатно получается bash-completion через `args::completion` — см. [examples/argsparseexample.sh](../../../examples/argsparseexample.sh).
- Более полный вариант такой утилиты: [examples/deploytoolexample.sh](../../../examples/deploytoolexample.sh).
