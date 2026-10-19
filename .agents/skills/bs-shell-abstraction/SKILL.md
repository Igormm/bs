---
name: bs-shell-abstraction
description: Remove the dependency of BS code on a particular command shell — move every BASH_SOURCE/BASH_VERSION/ZSH_*/$SHELL check into the abstraction layer (bootstrap/bs.sh, bootstrap/shell.sh), mark what cannot be abstracted with an `@shell` tier and a bilingual reason, support bash, zsh, ash, nushell first (then fish, ksh, osh), keep everything testable and honest about what was really run. Use when writing or changing any module, installer step, check or CLI command, or when sweeping the project for shell-specific code. Work happens on branch fix/kernel-security-p0, not on main.
type: prompt
whenToUse: When code touches shell detection, script paths, "run vs sourced", PATH/rc-file setup, installers, checks, or when a new lib/ or core/ module is added; also before merging kernel-security-p0 work
arguments:
  - scope
---

# Абстрагирование от командной оболочки / Shell abstraction

## Цель / Goal

BS со всеми абстракциями должен быть доступен из большинства оболочек, а не только из bash и zsh. **Приоритет задаёт таблица в `documentation/*/08-development/shell-portability.md`** (где оболочка встречается, версия, что запускалось на деле): сначала bash и zsh, затем dash и busybox ash, затем fish, ksh93, mksh, nushell; oksh и osh не развиваются. Абстрагируется всё: функции, установка, проверки, команды `bs`.
BS with all its abstractions must be reachable from most shells, not only bash and zsh. **The priority is set by the table in `documentation/*/08-development/shell-portability.md`** (where a shell is found, its version, what was really run): bash and zsh first, then dash and busybox ash, then fish, ksh93, mksh, nushell; oksh and osh are not developed. Everything is abstracted: functions, install, checks, `bs` commands.

## Модель: три оболочки / The model: three shells

| Роль | Что это | Правило |
|---|---|---|
| **host** | интерпретатор, исполняющий код BS | **зависит от яруса файла** (см. ниже): `@shell posix` — любая оболочка из таблицы; `@shell bash4` — bash ≥ 4.2, другую оболочку перезапускает в нём трамплин (`bootstrap/trampoline.sh`) |
| **оболочка пользователя** | где человек печатает команды; чей rc-файл правим | определяет реестр `bootstrap/shell.sh` (`--shell`, `BS_USER_SHELL`, родительский процесс, логин-оболочка) |
| **оболочка скрипта** | шебанг `#!/usr/bin/env bs` | не зависит от двух предыдущих |

Откуда запущен `bs`, помнит `BS_ORIGIN_SHELL` (её ставит трамплин).

## Зависимость от оболочки задаётся tier-ом / The shell dependency is set by tier

Раньше зависимость от bash 4 была размазана: проверки версии в точках входа, в `init.sh`, в `check_shell_environment`, оговорки в документации. **Теперь она задаётся один раз — меткой `# @shell posix|bash4` в заголовке файла**, и всё остальное выводится из неё.
The bash 4 dependency used to be scattered: version checks in the entry points, in `init.sh`, in `check_shell_environment`, caveats in the docs. **Now it is set once — by the `# @shell posix|bash4` label in the file header** — and everything else follows from it.

| Ярус / Tier | Где работает напрямую | Файлы сейчас |
|---|---|---|
| `posix` | bash, zsh, dash, busybox ash, ksh93, mksh | `bootstrap/shell.sh`, `trampoline.sh`, `shebang.sh`; `core/prereq`, `guard`, `const`, `version`, `quiet`, `fmt`, `logger`, `calc`, `data`, `utils`, `deps`, `errorhandler`, `config`, `lang` |
| `bash4` | bash 4.2+ (остальные оболочки — через перезапуск в bash или мост `bs call`) | `bootstrap/bs.sh`, `init.sh`, `loader.sh`; `core/lang`, `args`, `errorhandler`, `config`, `utils`, `deps` |

Следствия (правила для любого изменения):
1. **Метка — единственный источник правды.** Хозяин (host), `--strict-shell`, `bs doctor`, документация и `tier_scan.sh` читают её; новый файл без метки — `bash4`. Метку ставят честно и меняют только вместе с кодом: файл не `posix`, пока `dash -n`, `zsh -n`, `busybox ash -n` и тест под этими оболочками не проходят.
2. **Проверок версии оболочки в модулях нет.** Версию bash проверяют ровно два места: POSIX-пролог точек входа (`bs_shell_host_ok`) и `init.sh` в режиме source (там пролога нет, `bs::shell::ensure_version`). Повторы после пролога (в `bs`, `boot.sh`, `check_shell_environment`) удалены как лишние; не добавлять их снова. Модуль, которому «нужен bash 4», объявляет это меткой `@shell bash4`, а не `if (( BASH_VERSINFO ... ))`.
3. **Для оболочек, не покрытых ярусом, — мост, а не условия в коде.** fish, nushell и другие вызывают функции ядра командой `bs call`; запускать `bs` и `install.sh` можно из любой оболочки (пролог + трамплин).
4. **Перевод файла `bash4` → `posix`** — это смена метки плюс код, тест в 6 оболочках и строка в документации (таблица ярусов в `architecture.md`, раздел «POSIX-модули ядра»). Массивы и ассоциативные массивы заменяются слоем `core/data.sh` (`bs_arr_*`, `bs_map_*`), nameref — именем переменной и `eval`, `=~` — `case` и подстановками параметров; в `posix` не переводится только то, что по смыслу bash (`repl` вынесен в `lib/ui/repl`).
5. **Ярус `posix` проверяется машиной: bash в нём не участвует.** Команда `bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh` (код 1 при нарушении) для каждого файла с `# @shell posix` в `bootstrap/` и `core/` делает три вещи:
   - **разбор** файла в каждой установленной не-bash оболочке (`dash`, `busybox ash`, `ksh`, `mksh`, `zsh`);
   - **синтаксис**: в строках без комментариев нет `[[ ]]`, `(( ))`, массивов, `local -x`, `declare`, `${!x}`, `<( )`, `=~`, `mapfile`, `shopt`, `source`, ключевого слова `function`, `$'..'`, `${x^^}`; нет переменных `BASH_*`/`ZSH_*`/`FUNCNAME` вне файлов слоя (`bootstrap/shell.sh`, `trampoline.sh`); у файлов слоя разрешена только строка, которую они отдают **дочерней** оболочке (`"$1" -c '...'`);
   - **запуск без bash**: весь ярус подключается и работает в `dash` в песочнице, где в `PATH` нет bash вообще (`bs_version_get`, `bs_utils_has`, `bs_utils_ignore`…). Это доказывает не «парсится», а «bash не участвует».
   Оболочки, которых нет на машине, пишутся в отчёт как «не проверено» и никогда не считаются пройденными. Проверка запускается после любого изменения файла `posix`, при смене метки и перед коммитом; в CI её место — рядом с `tier_scan.sh --check`.
   The `posix` tier is checked by a machine: bash does not take part in it. `check_posix_tier.sh` (exit 1 on a violation) does, for every `# @shell posix` file in `bootstrap/` and `core/`: **parse** in every installed non-bash shell; **syntax** (no bash-only constructs on non-comment lines, no `BASH_*`/`ZSH_*`/`FUNCNAME` outside the layer files; layer files may only hold a string handed to a CHILD shell); **run without bash** (the whole tier is sourced and used by dash in a sandbox whose `PATH` has no bash — proof that bash does not take part, not just that it parses). Shells that are not installed are reported as "not verified", never as passed.
6. **Документация сначала называет требование, потом ярус.** BS требует bash 4.2+ (вся `lib/` и 1 из 15 файлов `core/`, а также CLI `bootstrap/bs.sh`, загрузчик и установщик); 8 файлов `@shell posix` и пролог — исключение. «Ядро делится на ярусы» без «нужен bash 4.2+» — преуменьшение, «нужен bash 4.2+» про ярус `posix` — преувеличение (см. навык `bs-docs-shell-claims`).

## Железные правила / Hard rules

1. **Ни одной оболочечной проверки вне слоя абстракции.** `BASH_SOURCE`, `BASH_VERSION`, `BASH_VERSINFO`, `BASH_EXECUTION_STRING`, `ZSH_*`, `$SHELL`, `$0` как путь скрипта — только в `bootstrap/bs.sh`, `bootstrap/shell.sh`, `bootstrap/trampoline.sh`, `init.sh`, `loader.sh` и точках входа до загрузчика. Всё остальное зовёт абстракцию:

   | Нужно | Звать |
   |---|---|
   | «меня запустили, а не подключили» | `bs::is_main` (не копировать `BASH_EXECUTION_STRING || BASH_SOURCE[0] == $0`) |
   | каталог своего файла | `bs::script_dir` |
   | имя / версия оболочки | `bs::shell::name`, `bs::shell::version`, `bs::shell::ensure_version` |
   | подключён ли файл | `bs::shell::is_sourced` |
   | путь своего файла | `bs::script_path` |
   | трассировка (файл, строка, функция кадра) | `bs::stack_depth`, `bs::stack_file L`, `bs::stack_line L`, `bs::stack_func L` |
   | строка версии оболочки | `bs::shell::version_string` |
   | префикс `set -x` | `bs::trace_prefix` |
   | оболочка пользователя, rc-файл, строка PATH, команда перезагрузки | `bs_shell_user`, `bs_shell_rc_file`, `bs_shell_path_line`, `bs_shell_reload_hint` (`bs::shell::*`) |
   | подходит ли tier файла оболочке запуска | `bs_shell_tier_allows`, `bs_shell_file_tier` |

   **Точки входа** (`bs`, `install.sh`, `boot.sh`, запускаемые раннеры `tests/run*.sh`, `tests/validate*.sh`) исполняются, а не подключаются, поэтому свой путь берут из POSIX `$0` + `readlink -f`, не из `BASH_SOURCE`. **Тесты** (`tests/**/test*.sh`) запускаются через `bs run` (его делает `tests/runalltests.sh`; вручную — `./bs run tests/unit/testX.sh`) и берут каталог из `bs::script_dir`; прямой `bash testX.sh` не поддерживается. Единственные исключения — тесты самого слоя абстракции (см. список в `scripts/find_leaks.sh`).
   **Исключений по файлам нет.** Свободны от проверки только сами файлы слоя (`bootstrap/bs.sh`, `shell.sh`, `trampoline.sh`); любое другое место — даже в `init.sh`, `loader.sh`, точках входа — должно звать реестр (`bs_shell_host_ok`, `bs_shell_family`, `bs_shell_of_name`) либо нести явный тег `shell-gate` в этой или одной из трёх предыдущих строк с объяснением, почему реестр туда не достать (сейчас так помечены 2 места в `init.sh`: до загрузки реестра из не-bash оболочки путь к нему неизвестен). Каталог `bootstrap/` все файлы берут из `BS_BOOTSTRAP_DIR`, его ставит `init.sh`.
   Нет нужной абстракции — **сначала добавьте её** в `bootstrap/bs.sh` (bash) или `bootstrap/shell.sh` (POSIX), потом используйте; не копируйте проверку в третий файл.
2. **Команды `bs` живут в `bootstrap/bs.sh` как `bs::cli::*`.** Файл `bs` — тонкая точка входа: пролог, загрузка ядра, флаги, диспетчер. Новую команду пишите как `bs::cli::<имя>`; имена без префикса (`help`, `die`) запрещены — они затеняют чужие.
3. **Неустранимая зависимость помечается, а не прячется.** Строка в заголовке файла: `# @shell posix|bash4 — <причина на русском> / <reason in English>`. Отсутствие метки = `bash4`. Синонимы: `sh`, `shell`, `posix` = posix; `bash`, `bash4` = bash4; `fs`, `fish` = fish; `nu`, `nushell` = nu; другое слово — оболочка с этим именем; список `a,b`. Это отдельная ось от `@tier core|gnu-linux` (какой userland нужен) — её не менять.
4. **POSIX-слой** (`@shell posix`): только функции `bs_shell_*` (dash не принимает `::`), без `[[ ]]`, массивов, `local -r`, `source`, `$'..'`; `::`-обёртки создаются `eval` только в bash/zsh. Проверка: `dash -n` и `shellcheck -s sh`.
5. **`--strict-shell` / `BS_SHELL_STRICT=1`** делает tier обязательным при `load` для `lib/`; `core/` (ядро) разрешено всегда. Tier нового модуля пишите честно — именно его проверяет строгий режим.
6. **Установка, проверки, удаление не предполагают bash/zsh:** rc-файл, синтаксис PATH, перезагрузка — через реестр; для nushell без `env.nu` — не создавать файл, а напечатать строку.
7. **Не врать о проверенном.** Оболочка, которую не запускали, помечается «не проверено». Сейчас реально запускались bash, zsh, dash, busybox ash, ksh93, mksh и fish (fish — только команда `bs` и скрипт с шебангом); не запускались nushell, oksh, osh (их нет на машине). Состояние ведёт таблица в `shell-portability.md`: обновляйте её по результатам настоящих запусков, а не по памяти.

## Решения по спорным случаям / Decisions for the hard cases

| Случай | Решение |
|---|---|
| Гейт «нужен bash 4.2+» в точке входа | пролог (одинаковый в `bs`, `install.sh`, `boot.sh`) подключает идемпотентный `bootstrap/shell.sh` и спрашивает `bs_shell_host_ok`; если нет — `trampoline.sh`. **Повторять проверку после пролога нельзя** (`ensure_version` в `bs`/`boot.sh`, `host_ok` в `check_shell_environment` удалены как лишние) |
| Вызвать функцию ядра из fish, nushell, dash | `bs call [--load МОДУЛЬ] ФУНКЦИЯ [АРГУМЕНТЫ]`; не писать «мост» заново, не вшивать оболочку в модуль |
| Шебанг не работает на машине (Termux: нет `/usr/bin/env`, `/bin/sh`) | `bs_shebang_fix` / `bs shebang`: установщик и `bs update` сами подгоняют `bs` и обёртку; в коде не ветвить по `uname` |
| Тот же гейт в `init.sh` (подключаемый файл) | остаётся встроенным и помечен `shell-gate`: из dash/zsh файл не знает своего каталога, реестр недостижим |
| Где лежит `bootstrap/` | `BS_BOOTSTRAP_DIR`: ставит `init.sh` (тег `shell-gate`), `bs.sh` подставляет по умолчанию; `loader.sh` и остальные только читают |
| Каталог точки входа | `BS_ENTRY_DIR`, считает пролог (тег `shell-gate`); `BS_DIR`/`SCRIPT_DIR`/`BOOT_DIR` берут его |
| Раннер или фикстура, исполняемые вне `bs` (`tests/run*.sh`, `validate*.sh`, скрипт во heredoc) | `$0` с тегом `shell-gate` и пояснением |
| Имя функции вызывающего (`FUNCNAME[1]`) | `bs::func_name N` (в `bs::func_name` N=1 — вызывающий; из функции X уровень вызывающего X — 2) |
| Файл, строка, функция кадра стека | `bs::stack_file/line/func L`, `bs::stack_depth` |
| Запуск дочерней оболочки (`bash -c`, `exec bash`, `/bin/bash`) | `"$(bs::shell::host)" -c ...` — тот же bash, что исполняет BS, а не первый в PATH |
| Особый случай для семейства (`bash`, `nu`) | функция реестра: `bs_shell_can_source`, `bs_shell_rc_create_ok`, `bs_shell_default_login_path`; сравнения `== "bash"` вне реестра запрещены |
| Опции bash (`shopt nullglob`) | не использовать: цикл по шаблону с проверкой `[[ -e ]]`; неизбежное (плагин Bash-it) — тег `shell-gate` |
| Автодополнение | `args::completion PROG [bash\|zsh\|fish\|nu]` (или `BS_COMPLETION_SHELL`); текст bash-completion — только в теле `args::completion` |
| Скрипт, установленный как wrapper | POSIX `#!/bin/sh`; bash находит `bs` сам |
| Имя запущенного скрипта | `bs::script_path` (под `bs run` и `$0` — путь скрипта) |
| Тесты слоя абстракции | перечислены в `scripts/find_leaks.sh`; остальные тесты — без `BASH_SOURCE` |

Тег ставят только тогда, когда реестр действительно недостижим; «так проще» — не причина.
Add the tag only when the registry really is unreachable; "it is simpler" is not a reason.

## Область: всё, что до lib/ / Scope: everything before lib/

**Задача ветки.** Всё, что загружается до `lib/` — `bootstrap/`, точки входа, `core/` — **не размазывает зависимость от оболочки**: она задана ярусом файла (`@shell`), а оболочки без bash получают ядро через перезапуск в bash, мост `bs call` и POSIX-ярус. Следов переменных оболочек (`BASH_*`, `ZSH_*`, `$SHELL`, …) нет нигде, кроме слоя абстракции (`bootstrap/shell.sh`, `bootstrap/bs.sh` до секции CLI, `trampoline.sh`) и строк с тегом `shell-gate`. Цель «всё ядро — POSIX» **не ставится**: `lang`, `args`, `repl` останутся `bash4`.
**The branch's task.** Everything loaded before `lib/` — `bootstrap/`, the entry points, `core/` — **does not scatter the shell dependency**: it is set by the file's tier (`@shell`), and shells without bash reach the kernel through a re-run in bash, the `bs call` bridge and the POSIX tier. No shell-variable traces anywhere but the abstraction layer and `shell-gate` lines. "The whole kernel is POSIX" is **not a goal**: `lang`, `args`, `repl` stay `bash4`.

**Решение: дублирование кода под оболочки — не грех.** Если одно и то же в bash, zsh и ash делается по-разному, пишем отдельную ветку на каждую оболочку внутри функции слоя (`case "$(bs_shell_family)" in bash) … ;; zsh) … ;; *) … ;; esac`), а потребитель зовёт одну функцию. Общий знаменатель любой ценой не нужен. Ветку для оболочки, которую не запускали, помечают «не проверено».
**Decision: duplicating code per shell is fine.** When bash, zsh and ash do the same thing differently, write one branch per shell inside a layer function; the consumer calls one function. A branch for a shell that was not run is marked "not verified".

**Tier каждого файла до lib/.** Метка `@shell` честно отражает язык файла:
- `posix` — работает в bash, zsh, dash, ash, ksh93, mksh: `bootstrap/shell.sh`, `trampoline.sh`, `shebang.sh`, прологи точек входа (`bs_shell_strict` — здесь же: `bs::strict` в `bootstrap/bs.sh` лишь вызывает её), `core/prereq`, `guard`, `const`, `version`, `quiet`, `fmt`, `logger`, `calc`, `data`, `utils`, `deps`, `errorhandler`, `config`, `lang`;
- `bash4` — остальное: `bootstrap/bs.sh`, `init.sh`, `loader.sh`, `core/lang`, `args`, `errorhandler`, `config`, `utils`, `deps` (массивы, ассоциативные массивы, `[[ ]]`, namerefs).
Перевод файла из `bash4` в `posix` — отдельная задача на файл: сначала список конструкций (`tier_scan.sh --list`), затем замена или вынос в ветку оболочки, затем `dash -n`, `zsh -n`, `busybox ash -n`, `ksh -n`, `mksh -n`, тест во всех шести. Оставшийся порядок (на слое `core/data.sh`): `core/utils` (остаток), `core/deps`, `core/lang`, `core/errorhandler`, `core/config` (`BS_CONFIG` → `bs_map_*`), `core/args`; затем `init.sh` и `loader.sh` (`BS_LOADED_MODULES` → `bs_map_*`), команды `bs::cli::*` (разрезать `bootstrap/bs.sh` по командам), `install/*`, и в конце точки входа `bs`, `boot.sh`, `install.sh`. Каждый шаг — отдельный коммит с тестом.

**Откуда берутся пути.** Источники пути только такие: `$0` в точке входа (пролог, тег `shell-gate`), `BS_ROOT`/`BS_ENTRY_DIR`/`BS_BOOTSTRAP_DIR`, `BS_CURRENT_FILE`, который ставит загрузчик на время `source`. Подключаемый файл не определяет свой путь сам.

## Порядок работы / Workflow

1. **Ветка.** Эта работа только в `fix/kernel-security-p0` (worktree), не в `main`. Историю не менять; коммит и push — по просьбе.
2. **Найти протечки:** `bash .agents/skills/bs-shell-abstraction/scripts/find_leaks.sh [paths]` (код 1, если есть). Затем `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check core lib bootstrap install` и **`bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh`** (bash в ярусе `posix` не участвует).
3. **Классифицировать каждую находку:** (a) дублирует существующую абстракцию → заменить вызовом; (b) нужна новая абстракция → добавить в слой, затем заменить все копии; (c) законно (трассировка стека, путь вызывающего в `prereq`) → оставить, при необходимости пояснить комментарием; (d) неустранима → метка `@shell` с причиной.
4. **Написать/обновить тест** в `tests/unit/` (изолированные `HOME`, `PATH`, `BS_SYSTEM_PREFIX`, `env -i`; настоящую установку не трогать, контрольная сумма `~/.local/lib/bs` и `~/.local/bin` до и после).
5. **Проверить в нескольких оболочках:** `dash ./bs …`, `zsh ./bs …`, bash как `sh`; для `@shell posix`-файлов — `dash -n`, `bash -n`, `zsh -n`.
6. **Цикл проверки:** `tests/validatesyntax.sh`, `tests/validateshellcheck.sh`, `tests/validatedocscode.sh`, `tests/runalltests.sh`.
7. **Документация и changelog:** `documentation/{en,ru}/08-development/shell-portability.md` (обе версии), строка в `CHANGELOG.md`; список навыков — `AGENTS.md`.
8. **Отчёт:** что абстрагировано, что помечено `@shell` и почему, какие оболочки запускались реально, какие нет; сколько протечек осталось.

## Чек-лист коммита / Commit checklist

- [ ] `find_leaks.sh` не вырос (идеально — 0 новых)
- [ ] у каждого нового файла есть `@shell` с причиной; `tier_scan.sh --check` — 0 нарушений
- [ ] нет новых проверок версии/семейства оболочки в модулях и после пролога: зависимость задана ярусом
- [ ] файл переведён в `posix` — проверен `X -n` и тестом в bash, zsh, dash, busybox ash, ksh, mksh
- [ ] `check_posix_tier.sh` — OK («bash в ярусе posix не участвует»); непроверенные оболочки названы в отчёте
- [ ] новая команда `bs` — `bs::cli::*` в `bootstrap/bs.sh`, не в `bs`
- [ ] тест проходит под bash; для POSIX-кода — под dash и zsh
- [ ] en и ru документация обновлены вместе
- [ ] в отчёте честно указано, что не запускалось
