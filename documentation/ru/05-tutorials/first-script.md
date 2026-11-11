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
# ↑ шебанг: скрипт запускает интерпретатор bs
log::info "Hello from BS"  # сообщение в лог с меткой времени
```

Shebang `#!/usr/bin/env bs` позволяет запускать скрипт напрямую в окружении BS (требуется `bs` в `PATH`). Из корня репозитория скрипт всегда можно запустить без установки:

```bash
./bs run deploy-lite.sh  # запустить скрипт
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
# ↑ шебанг: скрипт запускает интерпретатор bs

load "core/args"                                                # модуль разбора параметров

main() {                                                        # главная функция скрипта
    args::level 1 deploy status                                 # первое слово команды: deploy или status
    args::flag env value                                        # флаг --env со значением
    args::flag dry-run                                          # флаг-переключатель --dry-run

    args::describe deploy "Deploy the application"              # описание команды deploy для --help
    args::describe status "Show environment status"             # описание команды status для --help
    args::flag_describe env "Target environment: staging or production (default: staging)"  # описание --env для --help
    args::flag_describe dry-run "Print the plan without executing"  # описание --dry-run для --help
}                                                               # конец функции

main "$@"                                                       # вызвать main со всеми аргументами скрипта
```

- `args::level 1 deploy status` — на уровне 1 допустим `deploy` **или** `status` (ветвление дерева).
- `args::flag env value` — флаг со значением (`--env production` или `--env=production`).
- `args::flag dry-run` — булев флаг без значения.
- Флаги не занимают позиционные уровни: `deploy --dry-run` и `--dry-run deploy` эквивалентны.
- `args::describe` / `args::flag_describe` наполняют текст help. Валидация и help используют один источник данных, поэтому не могут разойтись.

Скрипт пока ничего нового не печатает — дерево объявлено, но не используется.

## Шаг 3: Валидация и автоматический help

Добавьте `args::require` после объявлений:

```bash
    args::require "$@"  # разобрать аргументы; при ошибке показать причину и справку
```

- При любом неверном вводе `args::parse` сам печатает причину и help в stderr и возвращает `E_INVALID` — `args::require` затем выходит с этим кодом через `bs::exit`, который выполняет стек очистки.
- `-h`/`--help` печатает help, и `args::require` выходит с кодом 0 — отдельная строка не нужна.
- `E_SUCCESS`, `E_ERROR`, `E_INVALID` (0/1/2) — константы из [core/const.sh](../../../core/const.sh), загружаемые точкой входа BS.

Запуск:

```bash
./bs run deploy-lite.sh --help  # показать автоматическую справку
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

После успешного `args::parse` позиционные параметры читаются через `args::param N [дефолт]` (счёт с 1, как у `$1`), а значения флагов — через `args::flag_get ИМЯ [запасное]`:

```bash
    local action                                                # переменная для команды
    action="$(args::param 1 status)"                            # первое слово; без него — status
    local env                                                   # переменная для окружения
    env="$(args::flag_get env staging)"                         # значение --env; без него — staging

    case "${env}" in                                            # проверить окружение
        staging|production) ;;                                  # допустимые значения: ничего не делаем
        *)                                                      # любое другое значение
            log::error "Unknown environment: ${env} (expected staging or production)"  # красное сообщение об ошибке
            bs::exit error                                      # выйти с кодом ошибки
            ;;                                                  # конец ветки
    esac                                                        # конец выбора

    if args::flag_get dry-run >/dev/null; then                  # если передан --dry-run
        log::warn "DRY RUN: no changes will be made"            # жёлтое предупреждение
    fi                                                          # конец условия
```

- `args::flag_get` печатает значение флага и возвращает 1, если флаг не задан, поэтому `|| printf 'staging'` задаёт значение по умолчанию.
- Уровень аргументов проверяет *синтаксис* (неизвестные имена, неверные уровни). *Семантические* проверки вроде «существуют только staging/production» остаются в скрипте: сообщайте о них через `log::error` и выходите с `E_ERROR`.
- `log::error` пишет в stderr, поэтому ошибки не попадают в stdout-конвейеры.

Запуск:

```bash
./bs run deploy-lite.sh deploy --env production --dry-run  # пробный запуск без изменений
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
./bs run deploy-lite.sh deploy --env mars  # неверное окружение: увидим ошибку
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
# ↑ шебанг: скрипт запускает интерпретатор bs

load "core/args"                                                # модуль разбора параметров
load "lib/io/streams"                                           # подключить модуль вывода

# ... inside main(), the status branch:
        status)                                                 # ветка команды status
            io::streams::printf '  %-11s %s\n' "environment" "${env}" "release" "v1.0.0" "health" "green"  # таблица из пар «имя значение»
            ;;                                                  # конец ветки
```

Запуск:

```bash
./bs run deploy-lite.sh status  # показать статус
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
# ↑ шебанг: скрипт запускает интерпретатор bs
# deploy-lite.sh — tiny deploy CLI: args + colored output + error handling

load "core/args"                                                # модуль разбора параметров
load "lib/io/streams"                                           # подключить модуль вывода

main() {                                                        # главная функция скрипта
    # 1. Declare the parameter tree and flags
    args::level 1 deploy status                                 # первое слово команды: deploy или status
    args::flag env value                                        # флаг --env со значением
    args::flag dry-run                                          # флаг-переключатель --dry-run

    args::describe deploy "Deploy the application"              # описание команды deploy для --help
    args::describe status "Show environment status"             # описание команды status для --help
    args::flag_describe env "Target environment: staging or production (default: staging)"  # описание --env для --help
    args::flag_describe dry-run "Print the plan without executing"  # описание --dry-run для --help

    # 2. Validate input; on error parse prints the reason and help itself
    args::require "$@"                                          # разобрать аргументы; при ошибке показать причину и справку

    # 3. Work with validated values
    local action                                                # переменная для команды
    action="$(args::param 1 status)"                            # первое слово; без него — status
    local env                                                   # переменная для окружения
    env="$(args::flag_get env staging)"                         # значение --env; без него — staging

    # Runtime validation: only two environments exist
    case "${env}" in                                            # проверить окружение
        staging|production) ;;                                  # допустимые значения: ничего не делаем
        *)                                                      # любое другое значение
            log::error "Unknown environment: ${env} (expected staging or production)"  # красное сообщение об ошибке
            bs::exit error                                      # выйти с кодом ошибки
            ;;                                                  # конец ветки
    esac                                                        # конец выбора

    if args::flag_get dry-run >/dev/null; then                  # если передан --dry-run
        log::warn "DRY RUN: no changes will be made"            # жёлтое предупреждение
    fi                                                          # конец условия

    case "${action}" in                                         # выбрать действие по команде
        deploy)                                                 # ветка команды deploy
            log::info "Deploying to ${env}..."                  # сообщить о начале
            io::streams::printf '  %-10s %s\n' "artifacts" "resolved" "release" "applied" "health" "green"  # таблица шагов
            log::success "Deploy to ${env} finished"            # зелёное сообщение об успехе
            ;;                                                  # конец ветки
        status)                                                 # ветка команды status
            io::streams::printf '  %-11s %s\n' "environment" "${env}" "release" "v1.0.0" "health" "green"  # таблица из пар «имя значение»
            ;;                                                  # конец ветки
    esac                                                        # конец выбора
}                                                               # конец функции

main "$@"                                                       # вызвать main со всеми аргументами скрипта
```

Проверьте путь ошибки валидации:

```bash
./bs run deploy-lite.sh fly  # неизвестная команда: увидим справку
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
