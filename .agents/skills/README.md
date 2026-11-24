# Скиллы BS по ярусам / BS skills by tier

Каталог рабочих скиллов `.agents/skills/`, разложенный по **ярусам (tier)** проекта.
Плоская раскладка каталогов сохраняется намеренно: обнаружение скиллов идёт по
`.agents/skills/<имя>/SKILL.md`; ярус — это метаданные `tier:` во frontmatter и
группировка в этом каталоге, а не вложенные папки.

### Вход / Entry

`bs-write-code` — входная точка: **любое** «напиши скрипт/программу/модуль/компонент/
posix-shell-скрипт/ядро/код под tier» начинается с него — он классифицирует ярус и
место, даёт скелеты и передаёт в профильный скилл яруса. / the entry point: **any**
"write a script/program/module/component/posix-shell script/kernel/tier code" starts
here — it classifies tier and location, gives the skeletons and hands off to the
per-tier skill.

## Что такое tier / What a tier is

Ярус — метка `# @shell posix|bash4` в заголовке файла, задающая, какая оболочка
исполняет код. Это единственное место, где зависимость от оболочки объявляется;
проверки `BASH_SOURCE`/`$SHELL` вне слоя абстракции запрещены.

| Ярус | Что входит | Где исполняется | Правила |
| --- | --- | --- | --- |
| `posix` | все 26 файлов `core/`, слой `bootstrap/` (shell/loader/base/init/kernel/cli/trampoline), `install/*`, прологи точек входа | bash, zsh, dash, busybox ash, ksh93, mksh — проверено запуском; bash в ярусе posix не участвует | глава 12 гайда, неймспейс `bs_`, алиасы `::` только в bash/zsh |
| `bash4` | вся `lib/` (87 модулей), `bootstrap/bs.sh` | только bash 4.2+; остальные оболочки попадают через трамплин/`bs call` | главы 1–11 гайда, `module::function`, `local`, массивы bash |
| pre-kernel | код до загрузчика: `bootstrap/base.sh` (posix), `bootstrap/bs.sh` (bash), прологи `bs`/`boot.sh`/`install.sh` | по ярусу файла; без абстракций core/lib | скиллы `bs-pre-kernel-*` |

Доктрина и проверки: `documentation/{en,ru}/02-core-concepts/architecture.md`
(«Ядро по ярусам»), `documentation/{en,ru}/08-development/shell-portability.md`
(таблица оболочек, что реально запускалось), глава 12
`documentation/{en,ru}/code-style-guide.md`; скрипты
`bs-shell-abstraction/scripts/check_posix_tier.sh` (разбор + синтаксис + прогон
без bash) и `bs-shell-portability/scripts/tier_scan.sh` (метки против конструкций).

## Настройки по ярусам / Settings per tier

Ярусы имеют **разные, местами противоположные** настройки — скиллы обязаны
применять колонку своего яруса, а не один набор к обоим (это главный источник
ложных замечаний в ревью).

| Настройка | `@shell posix` (core/, bootstrap/) | `@shell bash4` (lib/, bootstrap/bs.sh) |
| --- | --- | --- |
| Shebang + строка 2 | `#!/bin/sh`, `# shellcheck shell=sh` | `#!/usr/bin/env bs`, `# shellcheck shell=bash` |
| Метка яруса | `# @shell posix — причина` в первых 14 строках | `# @shell bash4 — причина` |
| Неймспейс | настоящие `bs_*`; `::` только через `bs_shell_alias` в конце | `module::function()`; приватные `module::__helper`/`_module_helper` |
| `local` / `[[ ]]` / массивы | **запрещены** (скретч-глобалы `__bs_*` вместо них) | разрешены (`local -r`, `[[ ]]`, assoc-массивы) |
| Source Guard | `bs_guard MODULE \|\| return 0` | `bs::guard "MODULE" \|\| return 0` |
| Строгий режим | никогда в модулях (только точки входа; `strict::enable`) | никогда в модулях (только точки входа) |
| Логирование / ошибки | `bs_log_*`; до логгера `printf '%s\n' "…" >&2` | `log::*`; `error::throw`; `utils::quiet` |
| Строки / коллекции | `bs_str_*`, `bs_arr_*`/`bs_map_*` (core/data.sh) | `str::*`, `arr::*`/`map::*` (настоящие массивы bash) |
| Коды | `0/1/2` + `LIB_ERROR_*` в форме `${E_ERROR:-1}` | `0/1/2` + `LIB_ERROR_*` |

zsh исполняет posix-ярус: не делит `$var` на слова, `readonly` внутри `load`
становится локальным (`bs_shell_readonly`), EXIT-ловушка из функции срабатывает
при возврате (`zshexit`), `${#s}` в dash/mksh считает байты.

Значения `tier:` у скиллов: `posix`, `bash4`, `both` (правила обоих ярусов),
`pre-kernel`, `doctrine` (скиллы о самих ярусах), `meta` (процесс: коммиты,
валидация, аудит, docs — от яруса не зависят).

## posix — ядро / the kernel

| Скилл | Назначение |
| --- | --- |
| `bs-kernel-code` | написать/перевести kernel-функцию в `bs_` как `@shell posix`: имена+алиасы, скелет, 6 оболочек, дифференциальный прогон |
| `bs-new-core-module` | новый модуль `core/` + регистрация (kernel.sh или on-demand load, doctor, счётчики ярусов) |
| `bs-posix-output` | ввод/вывод posix-яруса: возврат значений (§12.8), диагностика (§12.9), пользовательский вывод на `bs_log_*`, ловушки zsh/байтовых ширин |

## bash4 — lib/

| Скилл | Назначение |
| --- | --- |
| `bs-new-lib-module` | скелет нового модуля `lib/`: guard, зависимости, метаданные, юнит-тест |
| `bs-device-module` | Linux device/hardware модули (evdev/sysfs, бинарное декодирование, test hooks, деградация) |
| `bs-debug-logging` | отладка интерактивных bash-скриптов, гарантия «не без лога» (`lib/ui/steplog`) |

## pre-kernel — до загрузчика

| Скилл | Назначение |
| --- | --- |
| `bs-pre-kernel-namespace` | функции `bootstrap/bs.sh`, доступные ДО загрузчика |
| `bs-pre-kernel-boundary` | проверка границы: до load — без core/lib абстракций, после — обязательны |

## doctrine — о самих ярусах

| Скилл | Назначение |
| --- | --- |
| `bs-shell-portability` | модель host/user/script shell, аннотация `@shell`, трамплин, реестр оболочек, `tier_scan.sh`/`probe_shells.sh` |
| `bs-shell-abstraction` | зависимость от оболочки задаётся ярусом один раз; `find_leaks.sh`, `check_posix_tier.sh` |
| `bs-docs-shell-claims` | правка документов, утверждающих «всё ядро — bash 4», когда bash нужен только ярусу bash4 |

## both — оба яруса

| Скилл | Назначение |
| --- | --- |
| `bs-object-class` | класс на объектной модели `core/object.sh` (posix-модель, классы в bash4-модулях и posix-скриптах), глава 13 |
| `bs-regex` | два яруса regex: `core/regex.sh` (`bs_re_*`, POSIX ERE) vs `lib/data/regex.sh` (`regex::*`, ERE+PCRE), диалекты GNU/busybox/BSD |
| `bs-write-test` | юнит-тест (bash) + переносимый тест (6 оболочек), assert API testframework |
| `bs-review-module` | скептический обзор: bash-ловушки + kernel/posix чек-лист, §11, приоритизированные сомнения |
| `bs-variable-docs` |Двуязычные `# @global` для переменных модуля (§4.2) |
| `bs-variable-metadata` | метаданные переменных: `@var`, псевдотипы, `@ops`, валидация, хуки, схема |
| `bs-check-ansi` | ANSI-escape по проекту: `$'\033'` vs `printf '\033'`, никаких литералов в `printf %s` |
| `bs-code-review-security` | security-first ревью (инъекции, кавычки, пути, temp, привилегии, ярус, тесты), P0–P3 |
| `bs-cli-style` | стиль CLI-вывода: рамки, главное подсвечено, двуязычно, tty-цвет, человечные подсказки |
| `bs-cli-flags-style` | грамматика ключей docker/podman/go поверх `core/args` (RU) |
| `bs-cli-noop-output` | «нечего делать»: framed bilingual бокс, причины, next-step, exit 0 |
| `bs-cli-markdown-style` | принцип «простота markdown» для CLI/вывода/docs (RU) |
| `bs-scenario-audit` | сценарный аудит логики: шестичастная карточка, факт против ожидания, инвентарь по риску |

## meta — процесс, от яруса не зависит

| Скилл | Назначение |
| --- | --- |
| `bs-write-code` | входная точка «напиши код/скрипт/модуль/компонент/ядро BS»: классификация яруса и места, скелеты posix/bash4/bash4,zsh, конвенции, валидация, делегирование |
| `bs-validate` | обязательный цикл валидации + версия; долгие прогоны — в фон |
| `bs-version-bump` | бамп версии: единый источник `core/version.sh`, CHANGELOG, en/ru docs, no-bash тест |
| `bs-docs-sync` | синхронность en/ru документации и комментариев |
| `bs-commit-style` | Conventional Commits репозитория + безопасность истории |
| `bs-commit-pro` | атомарность по intent, staging, bisect/revert-безопасность, серии |
| `bs-audit` | полный аудит проекта цепочкой стадий с триажом |
| `bs-check-docs-code` | сниппеты в docs против реальности фреймворка |
| `bs-check-artifacts` | следы AI-генерации и утечки текста запросов |
| `bs-ai-toolchain` | BS как AI-toolbox: discovery, интроспекция, контракты генерации |
| `bs-code-design` | цепочка дизайна кода BS поверх методических скиллов |

## Импортированные скиллы (verbatim, не редактируются)

Классификация для навигации; файлы сохраняются как в upstream (лицензии в
`UPSTREAM.md` каждого скилла, см. AGENTS.md).

| Ярус | Скиллы |
| --- | --- |
| posix | `posix-shell` |
| bash4 | `bash-defensive-patterns` |
| both | `shell` |
| meta | `brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, `requesting-code-review`, `receiving-code-review`, `systematic-debugging`, `verification-before-completion`, `writing-skills`, `using-superpowers`, `dispatching-parallel-agents`, `subagent-driven-development`, `using-git-worktrees`, `finishing-a-development-branch`, `zero-hallucination-coder`, `named-persona-adversarial-review`, `pr-review-expert`, `changelog-generator`, `write-a-skill`, `grill-me`, `handoff`, `git-worktree-manager`, `doc-coauthoring` |
