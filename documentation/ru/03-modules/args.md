[↑ Оглавление](../README.md)

# Модуль args (`core/args.sh`)

Декларативное дерево параметров скрипта: допустимые параметры объявляются
один раз, а валидация, сообщения об ошибках, автоматический help и
bash completion получаются из одного источника данных.

## Загрузка

```bash
#!/usr/bin/env bs
load "core/args"
```

Или вручную, если скрипт запускается не под интерпретатором `bs`:

```bash
source bootstrap/init.sh
load "core/args"
```

## Линейная цепочка: `args::define`

Простейший случай — один параметр на уровень. Имя N занимает уровень N:

```bash
args::define first middle last
args::require "$@"
```

## Ветвление дерева: `args::level`

На одном уровне может быть несколько альтернатив. Уровни нумеруются с 1:

```bash
args::level 1 deploy rollback status
args::level 2 now later
```

`args::define a b c` — сокращение для трёх вызовов `args::level`.

## Описания: `args::describe`

Описания используются в `args::help`:

```bash
args::describe deploy "Deploy the application to servers"
args::describe now "Execute immediately"
```

## Флаги: `args::flag`, `args::flag_describe`, `args::flag_get`

Флаги (`--name`) не занимают позиционные уровни дерева. Два типа:

- `bool` (по умолчанию) — без значения: `--dry-run`
- `value` — требует значение: `--env production` или `--env=production`

```bash
args::flag dry-run                  # bool flag
args::flag env value                # value flag
args::flag_describe env "Target environment (staging, production)"

# After args::parse — value with a default:
env="$(args::flag_get env || printf 'staging')"

# Checking a bool flag:
if args::flag_get dry-run >/dev/null; then
    log::warn "DRY RUN"
fi
```

`args::flag_get` выводит значение и возвращает 0, если флаг был задан;
иначе ничего не выводит и возвращает `E_ERROR` (1).

Если загружен `core/utils`, последнюю проверку можно записать идиомой
тишины вместо явного перенаправления:

```bash
if utils::quiet args::flag_get dry-run; then ...; fi
```

## Валидация: `args::parse`, `args::get`

```bash
args::require "$@"
action="$(args::get 1)"
```

`args::require` — однострочник: при ошибке `args::parse` печатает
причину и help, затем выход с `E_INVALID` через `bs::exit` (выполняется стек
очистки); `--help` печатает help и выходит с кодом 0. Ручная двухшаговая
форма ниже — для случаев, где нужна своя обработка.

При успехе `args::parse` заполняет массив `ARGS_PARAMS` (позиционные
параметры, индексация с 0) и ассоциативный массив `ARGS_FLAGS` и возвращает
0. При ошибке печатает причину и help в stderr и возвращает `E_INVALID` (2):

- `ERROR: unknown parameter: "fly"`
- `ERROR: parameter "now" belongs to level 2, but was used at level 1`
- `ERROR: too many parameters: "x" is beyond level 2`
- `ERROR: unknown flag: "--bogus"`
- `ERROR: flag "--env" requires a value`

`-h` / `--help` печатает help в stdout, возвращает 0 и устанавливает
`ARGS_HELP_REQUESTED=1`:

```bash
if ! args::parse "$@"; then
    bs::exit invalid
fi
if [[ "${ARGS_HELP_REQUESTED}" == "1" ]]; then
    bs::exit success
fi
```

`args::get N` выводит провалидированный позиционный параметр на позиции N
(нумерация с 1) или возвращает `E_ERROR` (1), если позиция не задана.

## Help: `args::help`

Выводит справку, сгенерированную из того же дерева, что управляет
валидацией, — они никогда не расходятся:

```bash
args::help                # program name defaults to the $0 basename
args::help "deploy.sh"    # explicit program name
```

Вывод содержит строку usage (`Usage: deploy.sh [flags] [deploy|rollback|status] [now|later]`),
параметры по уровням с описаниями и секцию флагов.

## Bash completion: `args::completion`

Генерирует готовую функцию автодополнения bash из того же дерева и флагов:

```bash
args::completion "deploy.sh" > /etc/bash_completion.d/deploy.sh
source <(args::completion "deploy.sh")
```

Автодополнение знает варианты каждого уровня и объявленные флаги; значения
флагов типа `value` не дополняются.

## Сброс: `args::reset`

Очищает дерево, описания, флаги и разобранное состояние — нужен перед
повторным объявлением параметров в том же процессе:

```bash
args::reset
args::define first middle last
```

## Справочник API

| Функция | Назначение |
|---|---|
| `args::define a b c` | линейная цепочка, уровни 1..N |
| `args::level N a b ...` | допустимые альтернативы уровня N (с 1) |
| `args::describe name "text"` | описание параметра для help |
| `args::flag name [bool\|value]` | объявить флаг (по умолчанию `bool`) |
| `args::flag_describe name "text"` | описание флага для help |
| `args::flag_get name` | значение флага после `args::parse`; 1, если не задан |
| `args::parse "$@"` | валидация входных параметров по дереву |
| `args::get N` | провалидированный позиционный параметр N (с 1) |
| `args::help [prog]` | сгенерированный help |
| `args::completion [prog]` | генерация функции bash completion |
| `args::reset` | сброс дерева, флагов и разобранного состояния |

### Переменные состояния

| Переменная | Содержимое |
|---|---|
| `ARGS_PARAMS` | массив провалидированных позиционных параметров (с 0) |
| `ARGS_FLAGS` | ассоциативный массив провалидированных флагов (`"1"` для bool) |
| `ARGS_HELP_REQUESTED` | `1`, если передан `-h`/`--help` |
| `ARGS_VERSION` | версия модуля |

## Полный пример

См. [examples/argsparseexample.sh](../../../examples/argsparseexample.sh):

```bash
#!/usr/bin/env bs
load "core/args"

args::level 1 deploy rollback status
args::level 2 now later
args::describe deploy "Deploy the application to servers"
args::flag env value
args::flag dry-run
args::flag_describe env "Target environment (staging, production)"

if ! args::parse "$@"; then
    bs::exit invalid
fi
[[ "${ARGS_HELP_REQUESTED}" == "1" ]] && bs::exit success

action="${ARGS_PARAMS[0]:-status}"
env="$(args::flag_get env || printf 'staging')"
log::info "Action: ${action}, env: ${env}"
```

Запуск:

```bash
bs run examples/argsparseexample.sh deploy now --env production --dry-run
bs run examples/argsparseexample.sh --help
```
