---
name: bs-variable-metadata
description: Use when designing or implementing metadata for shell variables in BS — `# @var` annotations, pseudo-types, access/operation rules, validation, change hooks/logging, generated schema or audit — or when someone proposes rwx permissions, a protected variable store, or a preprocessor for shell variables.
type: prompt
whenToUse: Before writing `bs_var_*` metadata code, adding `@type`/`@ops` annotations, or reviewing a design that promises typed or access-controlled shell variables; also when a user asks for rwx/access control or pseudo-types on shell variables.
---

# BS variable metadata / Метаданные shell-переменных

## Главное правило / Core rule

**Сначала только метаданные. Не выдавать их за защиту.**

В shell нельзя перехватить обычное чтение или запись `$name`. Любой код в том
же процессе может прочитать переменную напрямую, сделать `eval`, `export` или
`unset`. Реально исполняются только `readonly`, `export` и `local`; и то
`readonly` не является границей безопасности — значение видно в `declare -p`,
уходит детям через `export`, доступно в `/proc/<pid>/environ` тому же
пользователю.

Поэтому:

- метаданные — это **контракт, валидация, рефлексия и аудит**;
- доступ `r/w` на обычную переменную — **совет**, а не enforcement;
- настоящее хранилище с проверкой доступа — отдельный слой `bs_store`, где
  значения лежат в map и прямого `$name` нет;
- не обещать «защищённые» или «типизированные» переменные, пока нет `bs_store`.

Если пользователь просит именно защиту, сначала объяснить эту границу и
предложить `bs_store`, а не прикручивать `rwx` к обычным переменным.

## Когда применять / When to use

- Добавляются `@type`, `@ops`, `@scope`, `@default`, `@range`, hooks для
  переменных.
- Проектируется реестр схем, генератор манифеста или аудит прямых обращений.
- Пользователь предлагает `rwx`-права, «типы» или препроцессор для shell-
  переменных.
- Нужно решить, где хранить метаданные: в комментариях, отдельной схеме или
  runtime-реестре.

Не применять для обычных `# @global`-доков — для них есть `bs-variable-docs`.
Не начинать с `bs_store`, если пользователь явно не просит enforced-хранилище.

## Порядок работы / Workflow

1. **Проверить фундамент.** В BS уже есть `core/var.sh`:
   `bs_var_is_name`, `bs_var_is_set`, `bs_var_is_readonly`, `bs_var_get`,
   `bs_var_set`, `bs_var_unset`, `bs_var_default`, `bs_var_append`. Расширять
   этот API, а не делать второй. Метаданные хранить в map из `core/data.sh`
   (`bs_map_*`), не в env.
2. **Выбрать один источник истины.** Для BS — аннотации рядом с объявлением,
   из них генерируется манифест. Не держать одновременно ручной список и
   комментарии: они разойдутся.
3. **Объявить схему.** Использовать `# @var NAME`, а не догадываться по
   следующему присваиванию. Разделить `@visibility`/`@scope` и
   `@description`: «private variable» — это не описание.
4. **Зарегистрировать в runtime.** `bs_var_declare NAME SPEC` создаёт запись
   только при вызове; на старте ничего не сканировать. В POSIX-ядре — только
   `case` и parameter expansion.
5. **Проверять при записи.** `bs_var_set/append/default` прогоняют
   `bs_var_validate`; политика `@on-invalid` решает: `error`, `warn`, `coerce`
   или `ignore`.
6. **Слать события.** `@on-change` и `@on-invalid` вызывают hook или пишут
   структурированный лог. Секреты не логировать.
7. **Сгенерировать манифест и аудит.** `scripts/gen_var_schema.sh` читает
   аннотации и создаёт `core/var-schema.sh`/JSON; CI проверяет дрейф.
   `scripts/check_var_contracts.sh` ищет прямые `$NAME`, присваивания и `eval`
   в обход API. Это аудит, не enforcement.
8. **Проверить в шести оболочках.** dash, ash, ksh, mksh, zsh, bash. Отдельно:
   `unset` vs empty, readonly, подоболочки, `export`, redaction, schema drift.
9. **Только после этого** обсуждать `bs_store` с реальным контролем доступа.

## Аннотации / Annotation block

`//` в shell невалиден. Использовать `#`:

```sh
# @var POSIX_SHELL_VARIABLE
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
# @deprecated use BS_NEW_VARIABLE
# @owner core/time
# @description ...
POSIX_SHELL_VARIABLE=0
```

Правила:

- `@var` обязателен; имя — `[A-Za-z_][A-Za-z0-9_]*`, не `__bs_var_*`
  (это временные `core/var.sh`).
- `@type` — псевдотип, не тип компилятора.
- `@ops` — список операций, а не `@function copy read`.
- `@access` можно поддержать как пресет для `@ops` (`ro`, `rw`, `rwe`), но
  источником истины оставить одно поле.
- `x` означать только `export`, не execute/eval.
- `@scope` — `global|module|function|local`; `@visibility` —
  `public|private|internal`.
- `@default` должен проходить ту же валидацию, что и `set`.
- `@description` — двуязычный, отдельно от видимости.

## Операции / Operations

Базовые операции:

| Операция | Смысл |
|---|---|
| `read` | получить значение через API |
| `write` | заменить значение |
| `append` | дописать |
| `unset` | удалить |
| `export` | отдать снимок в окружение детям |
| `snapshot` | снять копию значения и метаданных |
| `validate` | проверить без записи |
| `hash`/`compare` | безопасные операции без раскрытия |
| `watch` | подписаться на изменения |

`copy` = `read+snapshot`, `move` = `read+unset`, `link`/`alias` и `eval` —
отдельные опасные операции, по умолчанию запрещены. `rwx` не использовать:
`x` слишком двусмыслен.

Коды возврата `bs_var_*`: `0` успех, `1` нет переменной, `2` плохое имя,
предлагаемые `3` отказ по политике, `4` неверное значение. Не менять
существующие коды без миграции.

## Псевдотипы / Pseudo-types

Это runtime-валидаторы, не статические типы:

| Группа | Примеры |
|---|---|
| Скаляры | `string`, `name`, `int`, `uint`, `bool` |
| Домены | `enum:a\|b\|c`, `port`, `path`, `file`, `dir`, `command` |
| Форматы | `ipv4`, `ipv6`, `cidr`, `url`, `uuid`, `semver`, `regex` |
| Структуры | `list:<sep>`, `map` (bash4), `json` (внешний парсер) |
| Специальные | `secret`, `any` |

Обязательно:

- различать **unset**, **empty** и **default**;
- задать политику `strict|coerce|warn`;
- проверять `int` через `case`, а не `[ "$v" -eq ... ]` — иначе arithmetic
  injection;
- не тянуть `jq`/`realpath` в POSIX-ядро; для них — отдельный слой с честным
  `@requires`;
- канонизировать только явно (`@coerce`), не молча;
- `@range` и `@unit` хранить отдельно от `@type`.

Полный каталог и правила — в `reference.md`.

## События и логи / Events and logging

События: `declare`, `set`, `get`, `unset`, `export`, `validate-fail`,
`deprecated-use`, `scope-exit`. Поля записи: время, pid, глубина подоболочки,
имя, операция, результат, тип, caller, `value_hash`/`len`.

- `@secret yes`: в лог только имя, операция, длина и hash; значение — никогда.
- `@on-invalid error` — отвергнуть; `warn` — записать и пометить; `coerce` —
  записать преобразованное; `ignore` — записать как есть.
- `@on-change log:LEVEL|hook:function|none`; идемпотентную запись можно не
  логировать, если значение не изменилось.
- Защита от рекурсии: hook не должен писать в логируемые переменные.
- Не использовать `set -x` для секретов; `trap DEBUG` — только bash4 и не в
  горячем пути.
- Caller в POSIX ненадёжен; в bash есть `FUNCNAME`, но это не security.

## Препроцессор / Preprocessor mapping

Не делать текстовый препроцессор и не переписывать shell. Аннотации — вход
для генератора и проверяльщика.

| Директива | В BS |
|---|---|
| `#define`/`#undef` | `@const`, `@default`, сгенерированная схема |
| `#if`/`#ifdef` | runtime feature detection (`bs_utils_has`, `bs_shell_*`) |
| `#include`/guards | `bs_guard`, `bs_source_relative` |
| `#error`/`#warning` | ошибка в `bs_var_declare` или CI-проверка |
| `#line` | `@source file:line` для диагностики |
| `#pragma` | `@deprecated`, `@since`, `@flags` |
| stringify/paste | не нужно; в shell опасно |

Не парсить комментарии в runtime: это стоимость старта, риск инъекции и
отсутствие настоящего парсера shell.

## Типичные ошибки / Common mistakes

| Ошибка | Реальность |
|---|---|
| «`rwx` защитит `$var`» | Нет; прямой доступ и `eval` обходят API |
| `x` = execute/eval | Опасно; `x` — только export |
| `// @type` | Не shell-комментарий |
| `@function copy read` | Неясно; нужно `@ops read,copy` |
| `@description private variable` | Смешаны описание и видимость |
| `declare -i` для проверки int | Arithmetic injection; нужен `case` |
| `[ "$v" -eq 0 ]` до валидации | То же |
| `unset` считать пустым | Это разные состояния |
| Логировать значение секрета | Утечка; только hash/len |
| Парсить аннотации при каждом запуске | Медленно и опасно; генератор + CI |
| Два источника истины | Комментарии и ручная схема разойдутся |
| `::`-имя считать переносимым | Есть только в bash/zsh; в POSIX — настоящие имена |
| Писать в readonly | Завершает неинтерактивную оболочку; сначала `bs_var_is_readonly` |
| Забыть про dynamic scoping | `local` виден вызываемым функциям |
| Считать export безопасным | Значение уходит детям и в `/proc/.../environ` |
| Массивы в POSIX-ядре | Их нет; использовать `core/data` |
| Проверка доступа как security | Caller подделывается; это только аудит |
| Внешняя зависимость в core | Ломает POSIX/минимальный слой |

## Интеграция с BS / BS integration

- `core/var.sh` — единственный API; не создавать параллельный `var2`.
- Метаданные — `bs_map_*` из `core/data.sh`, лениво, только после
  `bs_var_declare`.
- POSIX-ядро: без `local`, `[[ ]]`, nameref и ассоциативных массивов.
- bash4-слой может дополнительно ставить `declare -r/-x` как отражение
  `readonly`/`export`, но это не отменяет валидацию; `declare -i` не
  использовать — он вычисляет арифметику до проверки.
- Существующие `# @global`-доки остаются; `bs-variable-docs` проверяет их.
  `@var` — новый слой метаданных, не замена.
- Имена функций: `bs_var_declare`, `bs_var_schema`, `bs_var_validate`,
  `bs_var_describe`, `bs_var_watch`; без `::`-алиасов в POSIX-ядре.
- Документация: en/ru синхронно, `code-style-guide` §4.2 и §12.

## Definition of done

- [ ] Аннотации используют `#`, `@var`, `@ops`, раздельные scope/visibility.
- [ ] `bs_var_declare` не сканирует код на старте.
- [ ] `bs_var_set/append/default` валидируют значение и соблюдают политику.
- [ ] `unset`, empty и default различаются и покрыты тестами.
- [ ] Секреты не попадают в логи, `set -x` и `export` без явного разрешения.
- [ ] Генератор манифеста и CI-проверка дрейфа есть.
- [ ] Аудит прямых обращений есть и честно назван аудитом.
- [ ] Тесты в dash, ash, ksh, mksh, zsh, bash.
- [ ] В документации написано: метаданные не защищают `$var`; для защиты —
      отдельный `bs_store`.
