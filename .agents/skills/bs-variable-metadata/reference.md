# Reference — variable metadata in BS

Дополнение к `SKILL.md`: полная таксономия, каталог псевдотипов, грамматика
аннотаций, формат событий и границы перехода к `bs_store`.

## 1. Таксономия возможностей компиляторов

| Категория | Что есть у компиляторов | Что реально в shell | Как оформить в метаданных |
|---|---|---|---|
| Объявление | declaration/definition, tentative, forward | `NAME=`, `: "${NAME:=}"`, `readonly` | `@var`, `@default` |
| Область | block/function/module/global | `local`, подоболочка, префикс модуля | `@scope`, `@visibility` |
| Время жизни | automatic/static/dynamic | процесс, функция, подоболочка, файл | `@scope`, `@lifetime` |
| Связывание | `extern`, `static`, `inline`, weak | `export`, source guard, module-private | `@visibility`, `@export` |
| Изменяемость | `const`, `final`, `readonly`, `volatile`, `atomic` | `readonly`; атомарности нет | `@ops read`, `@mutable` |
| Типы | primitive, enum, union, typedef, generic, nullable | только строки и runtime-валидация | `@type`, `@values`, `@nullable` |
| Уточнения | range, unit, refinement, dependent type | runtime-проверка | `@range`, `@unit`, `@pattern` |
| Инициализация | default, zero, lazy, once, порядок | `:-`, функция, guard | `@default`, `@lazy`, `@once` |
| Доступ | public/private/protected/internal, friend | конвенция и аудит | `@visibility`, `@ops` |
| Контракты | pre/post/invariant, assert | валидаторы, hooks | `@on-invalid`, `@invariant` |
| Владение | copy/move/borrow, lifetime, drop | копия значения, `unset`, cleanup stack | `@ops snapshot/move`, `@cleanup` |
| Побочные эффекты | pure, constexpr, noreturn | только метаданные | `@pure`, `@noreturn` |
| Наблюдаемость | trace, watchpoint, provenance | `set -x`, `trap DEBUG`, hooks | `@on-change`, `@source` |
| Параллельность | thread_local, atomic, memory_order | изоляция подоболочек, lock-файлы | `@concurrent`, `@lock` |
| Сериализация | schema, version, migration | `export`, manifest | `@schema-version`, `@migrate` |
| Рефлексия | debug info, symbol table | `declare -p`, `set`, `env`, API | `bs_var_describe`, `--json` |
| Безопасность | secret, taint, sanitize | redaction, права ОС | `@secret`, `@taint` |
| Оптимизация | inline, register, align, hot/cold | почти ничего | не моделировать |
| Препроцессор | define/include/if/pragma/error/line | генератор, runtime detection | `@if`, `@requires`, `@source` |

Важно: строки «что реально в shell» — не обещание. Это то, что можно проверить
API, но не то, что нельзя обойти прямым `$var`.

## 2. Каталог псевдотипов

| Тип | Проверка | Замечания |
|---|---|---|
| `string` | любая строка | без NUL; NUL shell не хранит |
| `name` | `[A-Za-z_][A-Za-z0-9_]*` | для имён модулей/функций |
| `int` | знак + цифры, затем range | без `eval`/`-eq` до проверки |
| `uint` | только цифры | 0..2^63-1 в арифметике shell |
| `bool` | `0|1|true|false` | выбрать один канон и алиасы |
| `enum` | значение из списка | список в схеме, не в коде |
| `port` | `1..65535` | не путать с сервисом |
| `path` | непустая строка | `file`/`dir` проверяют `test` |
| `file` | `-f` | symlink? решить явно |
| `dir` | `-d` | права отдельно |
| `command` | `command -v` | не запускать команду |
| `size` | число + unit | канон в байтах или unit отдельно |
| `duration` | число + unit | секунды/ms; не парсить `date` без нужды |
| `timestamp` | ISO-8601 или epoch | зафиксировать формат |
| `ipv4`/`ipv6`/`cidr` | синтаксис | без DNS |
| `url` | схема + host | не делать сетевой запрос |
| `uuid` | 8-4-4-4-12 | регистр канонизировать явно |
| `semver` | major.minor.patch | prerelease решить отдельно |
| `regex` | компилируется `grep -E`? | внешняя зависимость; пометить |
| `list` | разделитель | значения с разделителем escaping |
| `map` | bash4 assoc | в POSIX — `core/data` |
| `json` | `jq`/парсер | только lib/bash4, не core |
| `secret` | любая строка | redaction, запрет логов/export по умолчанию |
| `any` | без проверки | явное «не проверяем» |

Политики:

- `strict` — неверное значение отвергается (по умолчанию);
- `coerce` — привести к канону и записать;
- `warn` — записать, пометить `invalid=1`, позвать hook;
- `ignore` — записать как есть (только для совместимости).

Порядок: `default` → `coerce` → `validate` → `range`/`unit` → `hook`.

## 3. Грамматика аннотаций

Строки-аннотации начинаются с `#` и идут подряд над объявлением. Парсер
генератора простой: только `# @key value`, без анализа shell.

```sh
# @var NAME
# @type int
# @ops read,write,unset
# @scope module
# @visibility private
# @default 0
# @range 0..65535
# @unit bytes
# @on-invalid warn
# @on-change log:debug
# @secret no
# @since 0.9.2
# @deprecated use NEW_NAME
# @owner core/time
# @description ...
```

Допустимые сокращения:

- `@access ro|rw|rwe` — пресет для `@ops`; не дублировать оба поля;
- `@type enum:a|b|c` — вместо `@values`;
- `@ops none` — объявлена, но API запрещает всё;
- `@scope` по умолчанию `module`, `@visibility` — `private`.

Запрещено:

- `//`, `/* */`;
- `@function copy read` — операция и доступ в одном поле;
- `@description private` — видимость в описании;
- `@type integer` — использовать канон `int`;
- `@default $(...)` — выполнение кода при разборе; только литерал или имя
  функции.

## 4. Событие / Event record

Одна строка `key=value`, стабильный порядок, без значений секретов:

```text
ts=2026-10-26T12:00:00.000Z pid=4242 depth=0 var=POSIX_SHELL_VARIABLE
op=set result=ok type=int caller=core/time.sh:42 len=3 hash=fnv1a:...
```

Поля:

- `ts` — UTC, миллисекунды;
- `pid`, `depth` — процесс и глубина подоболочки;
- `var`, `op`, `result`;
- `type`, `scope`, `visibility`;
- `caller` — `file:line`/функция, если доступно; в POSIX может быть пусто;
- `len`, `hash` — вместо значения;
- `reason` — `range`, `enum`, `readonly`, `deprecated`, `secret-export`.

Уровни: `trace` (каждый get/set), `debug` (изменения), `info` (declare/unset),
`warn` (invalid/deprecated), `error` (отказ). В production по умолчанию `warn`.

## 5. Runtime-контракт (предлагаемый)

```sh
bs_var_declare NAME SPEC        # зарегистрировать схему
bs_var_schema NAME              # получить схему
bs_var_validate NAME VALUE      # 0 ok, 4 invalid, 3 denied
bs_var_get NAME [OUT]           # как сейчас: stdout или OUT
bs_var_set NAME VALUE           # проверка + hook
bs_var_append NAME VALUE
bs_var_unset NAME
bs_var_default NAME VALUE
bs_var_describe NAME [--json]   # рефлексия
bs_var_watch NAME HOOK          # подписка
```

Требования:

- `core/var.sh` остаётся POSIX; никаких `local`, `[[ ]]`, nameref;
- схема — в `bs_map_*`, не в env;
- `bs_var_declare` идемпотентен; повторная схема с другим типом — ошибка;
- `bs_var_set` на readonly сначала `bs_var_is_readonly` (иначе dash завершится);
- `bs_var_get` не логирует значение при `@secret`;
- статус `3` — только политика metadata-слоя, не security.

## 6. Генератор и аудит

`scripts/gen_var_schema.sh`:

1. читает `# @var`-блоки из `core/`, `lib/`, `bootstrap/`;
2. проверяет грамматику и уникальность;
3. генерирует `core/var-schema.sh` (POSIX `case`) и/или JSON для документации;
4. `--check` — сравнить с файлом в репозитории, exit 1 при дрейфе.

`scripts/check_var_contracts.sh`:

- ищет `$NAME`, `${NAME}`, `NAME=`, `unset NAME`, `export NAME`, `eval`;
- исключает объявления, `local`, `readonly`, сгенерированные файлы;
- выводит файл:строку и имя;
- это эвристика, не парсер shell; в отчёте так и писать.

## 7. Переход к `bs_store`

`bs_store` нужен, только если требуется реально запретить чтение/запись.
Тогда:

- значения лежат в map `bs_store_*`, прямого `$name` нет;
- все операции идут через `bs_store_get/set/unset/export`;
- `bs_store_export NAME` создаёт обычную переменную — это явный снимок, после
  которого метаданные и защита теряются;
- `bs_store` не заменяет `core/var`; это отдельный уровень;
- секреты в store всё равно не защищены от root/того же пользователя и от
  `gdb`/`/proc`; для настоящих секретов — файл `0600`, FD, secret manager.

## 8. План внедрения

1. **MVP:** `@var`-парсер, `bs_var_declare`, `bs_var_validate`, проверки в
   `set/append/default`, `describe`, тесты в шести оболочках.
2. **Наблюдаемость:** события, redaction, `@on-change`, `@on-invalid`.
3. **Генерация:** `core/var-schema.sh` + `--check` в CI.
4. **Аудит:** `check_var_contracts.sh`, отчёт, whitelist модулей.
5. **Документация:** en/ru, `code-style-guide` §4.2/§12, примеры.
6. **Только при доказанной потребности:** `bs_store`.

## 9. Открытые решения

- Где источник истины: аннотации или отдельный `schemas/vars.tsv`? Для BS —
  аннотации, генератор обязателен.
- Нужен ли `@access` как отдельное поле или только `@ops`? Один источник.
- Как определять caller в POSIX? Честно: часто никак; не делать вид, что это
  security.
- Нужны ли `@pure`/`@noreturn`? Только если аудит реально их использует.
- Нужен ли `json`-тип в core? Скорее нет; только lib/bash4.
- Как быть с `export` секрета? По умолчанию запрещать, разрешать явным
  `@ops export` + предупреждение.
