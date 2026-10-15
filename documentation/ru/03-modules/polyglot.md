[↑ Индекс документации](../README.md)

# Модуль `polyglot`

Запуск кода на **C, C++, Go, Rust, Python и JavaScript** прямо в скрипте bs:
аргументы передаются **туда**, результат возвращается **обратно** в переменные,
и с ним можно работать дальше.

Исходник: [lib/polyglot/run.sh](../../../lib/polyglot/run.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/polyglot/run"
```

## Контракт

| Направление | Как |
|---|---|
| скрипт → программа | аргументы после `--` (argv), `--env NAME=VALUE`, `--input TEXT` (stdin) |
| программа → скрипт | stdout в `--out VAR` (строка), `--lines VAR` (индексный массив) или `--map VAR` (ассоциативный массив, строки `ключ=значение`); код возврата в `--rc VAR` или статусом возврата |
| исходник | heredoc на stdin |

Значения не вставляются в исходник, поэтому переменная скрипта не может
внедрить код. Исходник исполняется с вашими правами: подавайте только
доверенный код.

## Примеры

```bash
#!/usr/bin/env bs

load "lib/polyglot/run"

# Число уходит туда, ответ возвращается в переменную
polyglot::run python --out answer -- 21 <<'PY'
import sys
print(int(sys.argv[1]) * 2)
PY
echo "${answer}"

# Несколько строк возвращаются массивом
polyglot::run js --lines words -- a b c <<'JS'
for (const w of process.argv.slice(2)) console.log(w.toUpperCase());
JS
echo "${#words[@]} слов"

# Строки key=value возвращаются ассоциативным массивом
declare -A cfg
polyglot::run c --map cfg --env NAME=bs <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) { printf("name=%s\nlen=2\n", getenv("NAME")); return 0; }
C
echo "${cfg[name]} ${cfg[len]}"

# С --rc код возврата не останавливает скрипт
polyglot::run python --rc code --out msg <<'PY'
import sys
print("bye")
sys.exit(3)
PY
echo "${code} ${msg}"
```

## Языки

| Язык | Псевдонимы | Инструмент (первый найденный) | Как запускается |
|---|---|---|---|
| `c` | — | `cc gcc clang` | компиляция, кэш |
| `cpp` | `c++`, `cxx`, `cc` | `c++ g++ clang++` | компиляция, кэш |
| `go` | `golang` | `go` | `go build`, кэш |
| `rust` | `rs` | `rustc` | компиляция, кэш |
| `python` | `py`, `python3` | `python3 python` | интерпретатор |
| `js` | `javascript`, `node` | `node bun` | интерпретатор |

`polyglot::languages` печатает таблицу с найденным на этой машине
инструментом (`-`, если его нет). Нет инструмента — `LIB_ERROR_DEPENDENCY_MISSING`,
сборка не удалась — `LIB_ERROR_DEPENDENCY` с выводом компилятора в журнале.

## Опции

`--out VAR`, `--lines VAR`, `--map VAR` (сначала `declare -A`), `--rc VAR`,
`--env NAME=VALUE` (можно повторять), `--input TEXT`, `--timeout SEC`
(`LIB_ERROR_TIMEOUT` при срабатывании), `--flags "…"` (дополнительные флаги
компилятора), `--no-cache`. Без `--out`/`--lines`/`--map` stdout программы
печатается.

## Кэш и хуки

Скомпилированные программы кэшируются в `POLYGLOT_CACHE_DIR`
(`~/.cache/bs/polyglot`) по хешу языка, компилятора (путь и версия), флагов и
исходника; первый запуск компилирует, последующие стартуют сразу. Порядок
поиска задают `POLYGLOT_C_TOOLS`, `POLYGLOT_CPP_TOOLS`, `POLYGLOT_GO_TOOLS`,
`POLYGLOT_RUST_TOOLS`, `POLYGLOT_PYTHON_TOOLS` и `POLYGLOT_JS_TOOLS`.

Смотрите также: [math](../../../lib/math/math.sh) — вычислитель на C, который
обобщает этот модуль.
