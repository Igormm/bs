---
name: bs-regex
description: Use when working with regular expressions in BS — choosing between core/regex.sh (POSIX ERE, bs_re_*) and lib/data/regex.sh (bash4/PCRE, regex::*), writing portable ERE, or handling GNU vs busybox vs BSD dialect differences and fallbacks.
type: prompt
whenToUse: Before writing a grep/sed/awk regex in a core or lib module, when porting a regex to busybox/ash, or when picking an engine (ERE vs PCRE) for a validation/extract/replace task.
---

# BS regex — два яруса, один диалект / two tiers, one dialect model

В BS регулярные выражения разделены по ярусам (`@shell`), а не по задачам:

| Ярус | Модуль | Пространство | Движки | Диалект |
|---|---|---|---|---|
| **posix** (dash/ash/ksh/mksh/zsh/bash) | `core/regex.sh` | `bs_re_*` | `grep -E`, `sed -E`, `awk` (с пробой и кэшем) | POSIX **ERE** |
| **bash4** | `lib/data/regex.sh` | `regex::*` | `[[ =~ ]]`, `grep -E/-P`, `sed -z`, `perl` | ERE + **PCRE** + многострочная замена |

Правило выбора:

- **Ядро (`core/`)** — только `bs_re_*` и только ERE: никаких `\d`, `\s`, lookaround.
- **`lib/`** — `regex::*`, можно `--pcre` для lookahead/backrefs/`\d`.
- **Валидация, извлечение, подсчёт, split** в posix — `bs_re_*`; **capture-группы и PCRE** — `regex::*`.

## Диалекты / Dialects

| Конструкция | POSIX BRE | POSIX ERE | PCRE | Замечание |
|---|---|---|---|---|
| `+`, `?`, `|` | `\+` `\?` `\|` | как есть | как есть | BRE требует экранирование |
| `()` группы | `\(` `\)` | как есть | как есть | |
| `\d`, `\s`, `\w` | нет | нет | да | в ERE заменять `[0-9]`, `[[:space:]]`, `[[:alnum:]_]` |
| lookahead/lookbehind | нет | нет | да | |
| backrefs `\1` | да (sed) | нет (grep -E) | да | |
| `\<` `\>` `\b` | GNU | GNU | да | в busybox/BSD могут не работать — используй `[[:<:]]`/`[[:>:]]` или не полагайся на них |

**Главное правило переносимости**: в posix-коде использовать `[[:space:]]`, `[[:digit:]]`, `[0-9]`, а не `\s`/`\d`.

## busybox vs GNU — gotchas

- `grep -o` — обычно есть, но если нет: `bs_re_find`/`bs_re_count` падают на `awk` (проба `__bs_re_grep_o`).
- `grep -P` — почти никогда нет в busybox; PCRE только в `lib/data/regex.sh` с fallback на `perl`.
- `sed -E` — есть, но нет `\U`/`\L`/`e`; `bs_re_replace` при отсутствии `-E` откатывается на BRE (`\(` `\)`).
- `awk` — busybox awk без `gensub`; используй POSIX `match`/`substr`/`split`/`gsub`.
- `sed -i` — busybox поддерживает, но синтаксис суффикса отличается; в `core/` не использовать `sed -i`.

`core/regex.sh` делает **пробу движков один раз и кэширует** (`__bs_re_grep_o`, `__bs_re_sed_e`, `__bs_re_awk`) — не плати за проверку на каждом вызове.

## API `core/regex.sh` (`bs_re_*`)

| Функция | Что делает | Аналог Python |
|---|---|---|
| `bs_re_match STR PATTERN` | есть ли вхождение ERE (0/1/2) | `re.search` |
| `bs_re_fullmatch STR PATTERN` | строка целиком (якоря `^()$`) | `re.fullmatch` |
| `bs_re_find STR PATTERN` | первое вхождение (stdout) | `re.search().group()` |
| `bs_re_count STR PATTERN` | число вхождений (stdout) | `len(re.findall)` |
| `bs_re_replace STR PAT REPL` | заменить все (`sed -E s///g`) | `re.sub` |
| `bs_re_split STR PATTERN` | разбить по ERE (`awk split`) | `re.split` |

Статусы: `0` найдено/успех, `1` нет/не найдено, `2` плохой паттерн. Предикаты использовать в `if`/`||` (не как standalone под `set -e`).

## Обработчики (как проектировать) / The handler model

Типовые операции ложатся в обработчики «данные → операция → инструмент → результат»:

1. **Validate** — `bs_re_match`/`bs_re_fullmatch` (и `regex::matches` для PCRE).
2. **Extract** — `bs_re_find`/`regex::find`; поле — `awk -F`.
3. **Replace** — `bs_re_replace`/`regex::replace` (многострочно в bash4).
4. **Filter** — `grep -E`/`-v` по строкам.
5. **Count** — `bs_re_count`/`grep -c`.
6. **Field** — `awk -F` + условие на поле.
7. **Normalize** — trim/collapse/case (`sed -E`).
8. **Structured** — INI/CSV/лог: `awk` + регулярки, не чистые regex.

Для каждого обработчика фиксируй **требуемый диалект** (BRE/ERE/PCRE, GNU-расширения) — это позволит выбрать реализацию под среду (ash vs bash, GNU vs busybox).

## Правила / Rules

1. В `core/` — только ERE и `bs_re_*`; `\d`/`\s`/lookaround — в `lib/data/regex.sh` с `--pcre`.
2. Паттерн в `grep`/`sed`/`awk` — через `-e`/`-v`, чтобы не ловить опции (`-`).
3. Числовые проверки диапазонов (0-255, даты) — НЕ одной регуляркой: регулярка на синтаксис, `awk` на диапазон.
4. `=~` в `core/` запрещён (bash-конструкция) — только `bs_re_match`.
5. Пробы движков кэшируются; не звать `grep -P`/`sed -z` на горячем пути.
6. Пиши портабельно: `[[:space:]]` вместо `\s`, `[0-9]` вместо `\d`.

## Источники / Sources

- GNU manuals (`grep`/`sed`/`gawk`) — эталонные расширения и семантика.
- POSIX (Open Group) — границы переносимости (BRE/ERE).
- Alpine wiki «Regex: Difference between revisions» — gotchas busybox.
- regular-expressions.info — сверка синтаксиса диалектов.
- man busybox — фактическая поддержка опций в целевой среде.

## Чек-лист / Checklist

- [ ] posix-код использует `bs_re_*` и ERE, без `\d`/`\s`/lookaround.
- [ ] PCRE/многострочная замена — через `lib/data/regex.sh` (`regex::*`, `--pcre`).
- [ ] паттерн передан через `-e`/`-v`, без опций-инъекций.
- [ ] диапазоны/даты проверены синтаксисом + численно (`awk`).
- [ ] busybox-фолбэки есть или явно помечены «требуется GNU».
- [ ] тесты в шести оболочках (`testregexportableunit.sh`) и в `testregexunit.sh`.
