[↑ Руководство разработчика](README.md)

# Переносимость между оболочками

BS должен работать из большинства оболочек, а не только из bash и zsh. Эта
страница — дизайн ветки `fix/kernel-security-p0`; рабочие правила для авторов
— в скилле `.agents/skills/bs-shell-portability/SKILL.md`.

## Три оболочки, а не одна

| Роль | Смысл | Кто определяет |
|---|---|---|
| **host** | интерпретатор, исполняющий код BS | всегда bash ≥ 4.2 (находит трамплин) |
| **оболочка пользователя** | где человек набирает команды; чей rc-файл получает PATH | `--shell`, `BS_USER_SHELL`, родительский процесс, логин-оболочка |
| **оболочка скрипта** | шебанг пользовательского скрипта (`#!/usr/bin/env bs`) | скрипт |

Ядру и `lib/` нужны массивы, namerefs, `[[ ]]`, `local -r`; они остаются
bash. От оболочки освобождено всё *вокруг*: точки входа, установщик, настройка
PATH, проверки, удаление, `bs where`.

## Режимы доступа

- **exec** — `bs ...` из любой оболочки. Точка входа начинается с
  POSIX-пролога; если интерпретатор — не bash ≥ 4 (или bash в режиме POSIX),
  подключается `bootstrap/trampoline.sh`: он находит подходящий bash и делает
  `exec` того же файла с теми же аргументами.
- **source** — `source bootstrap/init.sh`. Только bash 4.2+. В других
  оболочках — двуязычное сообщение вместо `Bad substitution`.
- **trampoline** — механизм первого режима. `BS_HOST_BASH=/path`
  переопределяет поиск (невалидное значение — ошибка, без тихого fallback).
  Если bash 4.2+ нет — подсказки по установке (apk/apt/dnf/brew) и код 1.

## Tier-ы

Две независимые оси:

- `@tier core | gnu-linux` — какой *userland* нужен модулю (без изменений).
- `@shell posix | bash4` — на каком *языке* написан файл. Отсутствие = `bash4`.
  После тире — двуязычная причина:
  `# @shell bash4 — используются массивы и [[ ]]`.

Итог для пользователя — `platform::get shell_tier`:

| tier | смысл |
|---|---|
| `native` | оболочка пользователя — bash 4.2+; BS можно подключать через source |
| `hosted` | другая оболочка; BS работает командой `bs`, исполняемой найденным bash |
| `unsupported` | на машине нет bash 4.2+ |

Неустранимая зависимость не скрывается: модуль помечен `bash4` и объясняет
причину в аннотации.

## Реестр оболочек — `bootstrap/shell.sh`

POSIX-код. Функции называются `bs_shell_*` (dash не принимает `::` в именах);
алиасы `bs::shell::*` создаются через `eval` только в bash/zsh. Знает семейства
`bash zsh dash ash sh ksh mksh oksh osh fish nu` и отвечает: `family`, `user`,
`rc_file`, `path_line`, `reload_hint`, `fresh_flags`, `all_rc_files`,
`host_find`, `tier`, `tier_desc`.

| оболочка | rc-файл | строка PATH |
|---|---|---|
| bash | `~/.bashrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| zsh | `${ZDOTDIR:-~}/.zshrc` | та же |
| dash, ash, sh, ksh, mksh, oksh | `~/.profile` | та же |
| osh | `~/.config/oils/oshrc` | та же |
| fish | `~/.config/fish/conf.d/bs.fish` | `contains -- … $PATH; or set -gx PATH …` |
| nu | `~/.config/nushell/env.nu` | `$env.PATH = ($env.PATH \| prepend …)` |

nushell: если `env.nu` нет, установщик его не создаёт, а печатает точную
строку для добавления.

## Строгий режим — `bs --strict-shell`

По умолчанию трамплин даёт любой оболочке любой модуль (код всегда исполняется
в bash). `--strict-shell` (или `BS_SHELL_STRICT=1`, нужен для shebang-режима)
делает tier `@shell` обязательным: модуль `lib/` загружается, только если его
tier подходит оболочке, из которой BS **запущен** (`BS_ORIGIN_SHELL`, её
экспортирует трамплин; bash, дошедший до трамплина, считается `sh`).

| tier модуля | разрешён из |
|---|---|
| `posix` | любой оболочки |
| `bash4` (по умолчанию) | bash 4.2+ |
| другое слово (`zsh`, `fish`, `nu`, …) | оболочки с этим именем |
| список `zsh,bash4` | любой из них |

Синонимы (слова tier и имена оболочек): `sh`, `shell`, `posix` = `posix`; `bash`, `bash4` = `bash4`; `fs`, `fish` = `fish`; `nu`, `nushell` = `nu`. Неизвестное слово остаётся как есть.

`core/` (ядро) разрешено всегда, иначе ничего не запустится. Отказ называет
модуль, его tier и исходную оболочку и завершается кодом 1:

```bash
dash ./bs --strict-shell run script.sh   # модуль lib/io/streams (@shell bash4) нельзя исполнять из 'dash'
```

## Приоритеты

1. bash, zsh, ash/dash, nushell — полный путь: установка, удаление, `bs where`,
   `bs init-shell`.
2. fish, ksh, mksh, oksh, osh — есть в реестре, те же пути кода.

## Что проверено

Реально запускалось: bash 5.3, zsh 5.9, dash 0.5.12 (синтаксис, точки входа,
трамплин, установка/удаление в изолированном `HOME`). **На настоящем
интерпретаторе не запускалось:** ash/busybox, ksh, mksh, oksh, osh, fish, nu —
проверены только генерируемые тексты (rc-файл, строка, команда перезагрузки).
Считайте их непроверенными.

## Тесты и инструменты

- `tests/unit/testshellunit.sh` — реестр; `testtrampolineunit.sh` — точки входа
  под dash/zsh/bash как sh; `testshelltierunit.sh` — аннотации;
  `tests/integration/testinstallshells.sh` — установщик по оболочкам.
- `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check <пути>`
  — аннотация против реальных конструкций.
- `bash .agents/skills/bs-shell-portability/scripts/probe_shells.sh` — проба
  возможностей установленных оболочек.

## Не сделано

Автодополнение для zsh/fish/nushell (есть только bash); аннотации `@shell`
вне bootstrap/install (по умолчанию `bash4`).
