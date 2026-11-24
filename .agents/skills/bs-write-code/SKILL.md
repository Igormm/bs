---
name: bs-write-code
description: Написать код для BS — скрипт, программу, пример, lib-модуль, core-компонент/модуль/функцию, posix-shell скрипт, bash4-код или код под tier bash4,zsh. Входная точка фреймворка для ИИ-агента — классификация яруса и места, скелет, конвенции, валидация, делегирование профильным скиллам. / Write BS code — a script, program, example, lib module, core component/module/function, posix-shell script, bash4 or bash4,zsh tier code. The framework entry point for an AI agent — tier and location classification, skeleton, conventions, validation, delegation to per-tier skills.
type: prompt
whenToUse: Когда пользователь пишет «напиши скрипт», «напиши программу на bs», «напиши модуль/компонент bs», «напиши core модуль/функцию», «напиши posix-shell скрипт/компонент», «напиши под tier bash4 или zsh или bash4,zsh», «создай lib модуль», «добавь функцию/компонент в ядро» — любое создание кода в репозитории BS, до выбора яруса и места. / When the user writes "write a script", "write a bs program", "write a bs module/component", "write a core module/function", "write a posix-shell script", "write bash4/zsh/bash4,zsh tier code", "create a lib module", "add a function to the kernel" — any code creation in this repo, before the tier and location are chosen.
tier: meta
arguments:
  - request
---

# Написать код для BS / Writing BS code

Это **входной скилл**: модели и агенты не читают `AGENTS.md` и гайды заранее,
поэтому правила фреймворка собраны здесь как дерево решений. Не пиши код, пока не
прошёл шаги 0–2; дальше применяется скилл соответствующего яруса (шаг 5).

This is the **entry skill**: models and agents do not read AGENTS.md and the
guides up front, so the framework rules are gathered here as a decision tree. Do
not write code before steps 0–2; then apply the matching per-tier skill (step 5).

## 0. Сначала классифицируй, потом пиши / Classify first

Два вопроса, ответ обязателен до кода / two questions, answer before coding:

1. **Что** создаём: скрипт/программа/пример → `examples/`; библиотечный модуль →
   `lib/`; ядро (модуль/функция) → `core/` (или `bootstrap/`, `install/`).
2. **Какой ярус** `@shell`: `posix` | `bash4` | `bash4,zsh` (список = «или»).

Новый файл **без** метки = `bash4`. Метка — в **первых 14 строках**, с двуязычной
причиной / no annotation = `bash4`; the marker goes in the **first 14 lines** with
a bilingual reason.

## 1. Что и куда / What and where

| Артефакт / Artifact | Место / Location | Шаблон / Skeleton |
| --- | --- | --- |
| Программа / скрипт / пример (точка входа) | `examples/<name>.sh` | `#!/usr/bin/env bs`, `# shellcheck shell=bash`, `name::func` + `main()` |
| Библиотечный модуль (ярус bash4) | `lib/<group>/<module>.sh` | `#!/usr/bin/env bs`, `group::module::func` |
| Ядро — модуль/функция (ярус posix) | `core/<module>.sh` | `#!/bin/sh`, `# shellcheck shell=sh`, `bs_<module>_<func>` (+ `::`-алиасы) |
| bootstrap / install / пролог точек входа | `bootstrap/`, `install/`, `bs` | `#!/bin/sh`, неймспейс `bs_*` |
| Демо ядра | `example_core/` | через `load "core/..."`, функции ядра |

### Компоненты по ярусам / Components per tier (файлы, функции, классы)

| Компонент / Component | Ярус / Tier | Реализация / Realisation | Скилл / Skill |
| --- | --- | --- | --- |
| Файл/модуль ядра | posix | `core/`, `bootstrap/`, `install/`; `#!/bin/sh` | `bs-new-core-module` |
| Файл/модуль библиотеки | bash4 | `lib/`; `#!/usr/bin/env bs` | `bs-new-lib-module` |
| Функция ядра | posix | `bs_module_func`, без `local`/`[[ ]]`/массивов; `::` только через `bs_shell_alias` | `bs-kernel-code` |
| Функция библиотеки | bash4 | `module::func`, `local`, `[[ ]]`, массивы | `bs-new-lib-module` |
| Класс (объектная модель) | posix-ядро `core/object.sh`; используется и в bash4 | настоящие `bs_obj_*`; псевдонимы `object::*` в bash/zsh; глава 13, эталоны `example_core/{counter,shapes}.sh` | `bs-object-class` |
| Регулярные выражения | both | `core/regex.sh` (`bs_re_*`, POSIX ERE) vs `lib/data/regex.sh` (`regex::*`, ERE+PCRE) | `bs-regex` |
| Устройство/железо | bash4 | evdev/sysfs, тестовые хуки, деградация | `bs-device-module` |
| Тест | both | `tests/unit/*` (bash) + переносимый (6 оболочек) | `bs-write-test` |
| Переменные/метаданные | both | `@var`, `@global`, `@ops` | `bs-variable-metadata`, `bs-variable-docs` |

## 2. Ярус @shell / The @shell tier

| Правило / Setting | `posix` (`core/`, `bootstrap/`, `install/`) | `bash4` (`lib/`, `bootstrap/bs.sh`, скрипты) |
| --- | --- | --- |
| Шебанг + строка 2 | `#!/bin/sh` + `# shellcheck shell=sh` | `#!/usr/bin/env bs` + `# shellcheck shell=bash` |
| Метка яруса | `# @shell posix — причина` (RU/EN) | `# @shell bash4 — причина` |
| Неймспейс | настоящие `bs_*`; `::` только через `bs_shell_alias` в конце файла | `module::function`; приватные `module::__helper` |
| `local` / `[[ ]]` / массивы / `$'..'` | **запрещены** — скретч-глобалы `__bs_<модуль>_*` | разрешены (`local -r`, `[[ ]]`, assoc-массивы) |
| Source Guard | `bs_guard MODULE \|\| return 0` | `bs::guard "MODULE" \|\| return 0` |
| Зависимости | `bs_source_relative ...` | `bs::source_relative ...` + `# @depends ...` |
| Строгий режим | никогда в модулях (только точки входа) | никогда в модулях (только точки входа) |
| Логирование / ошибки | `bs_log_*`; до логгера `printf >&2` | `log::*`, `error::throw`, `utils::quiet` |

**Список ярусов** (`@shell bash4,zsh`) значит «bash 4.2+ **или** zsh» — проверяет
`bs_shell_tier_allows`. Используй его, когда код **держит** bash-конструкции
(массивы, `[[ ]]`), но обязан запускаться ещё и в zsh: тогда добавь zsh-шим:
`[[ -n "${ZSH_VERSION:-}" ]] && setopt KSH_ARRAYS SH_WORD_SPLIT no_nomatch` перед
первым обращением к массивам, и **докажи** запуск (`zsh -n` + реальный прогон).
Не пиши `posix`, если файл не разбирается в `dash -n` — в ярусе posix bash не
участвует.

A tier **list** (`@shell bash4,zsh`) means "bash 4.2+ **or** zsh" — enforced by
`bs_shell_tier_allows`. Use it when the code **needs** bash constructs (arrays,
`[[ ]]`) but must also run under zsh: add the zsh shim above before the first
array access and **prove** it (`zsh -n` + a real run). Do not write `posix`
unless the file parses in `dash -n`.

## 3. Скелеты / Skeletons

### lib-модуль (bash4)

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# lib/group/module.sh — одно строкой (двуязычный заголовок ru/en)
# @depends core/const, core/logger, core/utils

bs::guard "GROUP_MODULE" || return 0

bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# shellcheck disable=SC2034
declare -g GROUP_MODULE_VERSION="1.0.0"

group::module::function() {     # @description Public API (bilingual DocBlock)
    local -r arg="${1:?argument required}"
    ...
}
```

### core-модуль (posix) — эталон `core/fmt.sh`

```bash
#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, date / valid POSIX sh: case, parameter expansion, date
# @tier core — date, awk; works everywhere
# core/module.sh — двуязычное описание / bilingual description

bs_guard MODULE || return 0

bs_source_relative ../const.sh ../logger.sh

bs_module_func() {              # @description / @param / @stdout
    __bs_module_tmp=${1:-}       # скретч-переменные __bs_<модуль>_*, без local
    ...
}

# Псевдонимы для bash/zsh в конце файла / aliases at the end:
bs_shell_alias bs_module_func module::func
```

## 4. Конвенции / Conventions (код-стайл, все ярусы)

- `snake_case` + неймспейс; `SCREAMING_SNAKE_CASE` у `readonly`-констант; **без**
  CamelCase/mixedCase (guide §2.1).
- Двуязычные комментарии (RU first); вывод CLI — по `bs-cli-style` (рамки, главное
  подсвечено, без `===`-арта).
- Абстракции вместо сырых команд: `utils::has` вместо `command -v ...`,
  `utils::quiet`/`utils::quiet_err`/`utils::ignore` вместо редиректов, `is::*` вместо
  флагов `[[ -f/-d/-z ]]`; в posix — `bs_utils_*`/`bs_is_*`.
- Строгий режим только в точках входа (`strict::enable`). Интерактивный TUI/скрипт
  — честно `set -u` вместо `-e` и комментарий «почему» (см. `examples/dripfetch.sh`).
- Новая публичная функция ⇒ тест `tests/unit/test<name>unit.sh` (скилл `bs-write-test`)
  и двуязычный `@description`.

## 5. Делегирование / Delegate to the per-tier skill

| Если / If | Загрузи / Load |
| --- | --- |
| Ядро / core (posix) | `bs-kernel-code`, `bs-new-core-module`, `bs-posix-output` |
| lib/ (bash4) | `bs-new-lib-module`, `bs-logging`, `bs-cli-style` |
| Класс (объектная модель) | `bs-object-class` |
| Регулярные выражения | `bs-regex` |
| Устройство/железо | `bs-device-module` |
| До ядра (bootstrap/bs.sh, прологи) | `bs-pre-kernel-namespace`, `bs-pre-kernel-boundary` |
| Про сами яруса / аннотации | `bs-shell-portability`, `bs-shell-abstraction` |
| Тест | `bs-write-test` |
| Метаданные переменных | `bs-variable-metadata`, `bs-variable-docs` |
| Дизайн-цепочка целиком | `bs-code-design` (brainstorm → map → plan → TDD → verify) |

## 6. Валидация / Validation (обязательно, ДО «готово»)

```bash
bash tests/validatesyntax.sh
bash tests/validateshellcheck.sh                 # гейт: shellcheck --severity=error
bash tests/runalltests.sh
# для @shell posix дополнительно:
bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh
bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check
# для @shell bash4,zsh или любого «+zsh»:
zsh -n FILE && (реальный прогон скрипта под zsh)
```

## 7. Честность / Honesty

- Докажи, потом утверждай (`verification-before-completion`); оболочку без
  реального прогона помечай «не проверено», а не «поддерживается».
- Не протекай текст запроса в код/доки (`bs-check-artifacts`); en/ru доки синхронны
  (`bs-docs-sync`); история git неизменна (`bs-commit-style`).
