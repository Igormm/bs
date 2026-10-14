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

BS со всеми абстракциями должен быть доступен из большинства оболочек, а не только из bash и zsh. **Приоритет: bash, zsh, ash, nushell**; fish, ksh, mksh, oksh, osh — ниже, но есть в реестре. Абстрагируется всё: методы и функции, установка, проверки, команды `bs`.
BS with all its abstractions must be reachable from most shells, not only bash and zsh. **Priority: bash, zsh, ash, nushell**; fish, ksh, mksh, oksh, osh are lower but in the registry. Everything is abstracted: functions, install, checks, `bs` commands.

## Модель: три оболочки / The model: three shells

| Роль | Что это | Правило |
|---|---|---|
| **host** | интерпретатор, исполняющий код BS | всегда bash ≥ 4.2; другую оболочку перезапускает в нём трамплин (`bootstrap/trampoline.sh`) |
| **оболочка пользователя** | где человек печатает команды; чей rc-файл правим | определяет реестр `bootstrap/shell.sh` (`--shell`, `BS_USER_SHELL`, родительский процесс, логин-оболочка) |
| **оболочка скрипта** | шебанг `#!/usr/bin/env bs` | не зависит от двух предыдущих |

Откуда запущен `bs`, помнит `BS_ORIGIN_SHELL` (её ставит трамплин).

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
7. **Не врать о проверенном.** Оболочка, которую не запускали (ash/busybox, ksh, mksh, oksh, osh, fish, nu — если их нет на машине), помечается «не проверено»; проверены только сгенерированные тексты.

## Порядок работы / Workflow

1. **Ветка.** Эта работа только в `fix/kernel-security-p0` (worktree), не в `main`. Историю не менять; коммит и push — по просьбе.
2. **Найти протечки:** `bash .agents/skills/bs-shell-abstraction/scripts/find_leaks.sh [paths]` (код 1, если есть). Затем `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check core lib bootstrap install`.
3. **Классифицировать каждую находку:** (a) дублирует существующую абстракцию → заменить вызовом; (b) нужна новая абстракция → добавить в слой, затем заменить все копии; (c) законно (трассировка стека, путь вызывающего в `prereq`) → оставить, при необходимости пояснить комментарием; (d) неустранима → метка `@shell` с причиной.
4. **Написать/обновить тест** в `tests/unit/` (изолированные `HOME`, `PATH`, `BS_SYSTEM_PREFIX`, `env -i`; настоящую установку не трогать, контрольная сумма `~/.local/lib/bs` и `~/.local/bin` до и после).
5. **Проверить в нескольких оболочках:** `dash ./bs …`, `zsh ./bs …`, bash как `sh`; для `@shell posix`-файлов — `dash -n`, `bash -n`, `zsh -n`.
6. **Цикл проверки:** `tests/validatesyntax.sh`, `tests/validateshellcheck.sh`, `tests/validatedocscode.sh`, `tests/runalltests.sh`.
7. **Документация и changelog:** `documentation/{en,ru}/08-development/shell-portability.md` (обе версии), строка в `CHANGELOG.md`; список навыков — `AGENTS.md`.
8. **Отчёт:** что абстрагировано, что помечено `@shell` и почему, какие оболочки запускались реально, какие нет; сколько протечек осталось.

## Чек-лист коммита / Commit checklist

- [ ] `find_leaks.sh` не вырос (идеально — 0 новых)
- [ ] у каждого нового файла есть `@shell` с причиной; `tier_scan.sh --check` — 0 нарушений
- [ ] новая команда `bs` — `bs::cli::*` в `bootstrap/bs.sh`, не в `bs`
- [ ] тест проходит под bash; для POSIX-кода — под dash и zsh
- [ ] en и ru документация обновлены вместе
- [ ] в отчёте честно указано, что не запускалось
