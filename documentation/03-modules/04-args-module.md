# Модуль args (core/args.sh)

Декларативное дерево параметров скрипта: валидация, авто-help и
bash-completion из одного источника данных.

A declarative script parameter tree: validation, auto-help and
bash completion from a single source of truth.

## Загрузка / Loading

```bash
load "core/args"
```

## Линейная цепочка / Linear chain

Эквивалент `parameters("first", "middle", "last")` — имя N занимает уровень N:

```bash
args::define first middle last
args::parse "$@" || exit $?
```

## Ветвление дерева / Tree branching

На одном уровне может быть несколько альтернатив:

```bash
args::level 1 deploy rollback status
args::level 2 now later
```

## Флаги / Flags

Флаги не занимают позиционные уровни:

```bash
args::flag verbose            # --verbose (bool)
args::flag output value       # --output file или --output=file
args::flag_describe output "Write the report to this file"

file="$(args::flag_get output || printf 'default.log')"
```

## Валидация / Validation

`args::parse "$@"` заполняет `ARGS_PARAMS` и `ARGS_FLAGS`, а при ошибке
печатает причину и help в stderr и возвращает `E_INVALID` (2):

- `ERROR: unknown parameter: "fly"`
- `ERROR: parameter "now" belongs to level 2, but was used at level 1`
- `ERROR: too many parameters: "x" is beyond level 3`
- `ERROR: unknown flag: "--bogus"`
- `ERROR: flag "--output" requires a value`

`-h` / `--help` печатает help и возвращает 0 с `ARGS_HELP_REQUESTED=1`.

## Help и completion / Help and completion

```bash
args::help "deploy.sh"                    # usage + параметры + флаги
args::completion "deploy.sh"              # готовая bash completion функция
source <(bs run myscript.sh --emit-completion)
```

Help никогда не расходится с валидацией — генерируется из того же дерева.

## API

| Функция | Назначение |
|---|---|
| `args::define a b c` | линейная цепочка уровней 1..N |
| `args::level N a b` | альтернативы уровня N |
| `args::describe name "text"` | описание параметра для help |
| `args::flag name [bool\|value]` | объявить флаг |
| `args::flag_describe name "text"` | описание флага |
| `args::flag_get name` | значение флага после parse |
| `args::parse "$@"` | валидация входных параметров |
| `args::get N` | позиционный параметр N (1-based) |
| `args::help [prog]` | сгенерированный help |
| `args::completion [prog]` | генерация bash completion |
| `args::reset` | сброс дерева и флагов |

## Пример / Example

См. `examples/argsparseexample.sh`:

```bash
bs run examples/argsparseexample.sh deploy now --env production --dry-run
```
