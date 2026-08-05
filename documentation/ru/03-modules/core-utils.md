[↑ Оглавление](../README.md)

# core/utils

Утилиты общего назначения. Исходник: [core/utils.sh](../../../core/utils.sh).

## Доступность

`core/utils` загружается автоматически при бутстрапе ([bootstrap/init.sh](../../../bootstrap/init.sh)),
поэтому его функции доступны в любом модуле и любом скрипте после бутстрапа — явный
`load "core/utils"` не нужен.

Важно: `core/utils` загружается **последним** из core-модулей (`core/const`, `core/logger`,
`core/errorhandler`, `core/version`, `core/utils`). Поэтому сами core-модули хелперы
`utils::*` не используют — на момент их загрузки этих функций ещё нет.

## Справочник функций

### utils::strict

```bash
utils::strict
```

Включает строгий режим для текущего shell: `set -euo pipefail` и `IFS=$'\n\t'`.
Вызывайте в точке входа скрипта. Подключаемые файлы библиотек не должны включать
строгий режим сами, поэтому это оставлено вызывающей стороне.

### utils::guard

> **Deprecated.** Используйте `bs::guard` из [core/prereq.sh](../../core/prereq.sh):
> `bs::guard "foo" || return 0` — проверяет метку и выставляет её за один вызов.
> `utils::guard` оставлен как check-only алиас (`bs::guard_loaded`) для обратной
> совместимости.

```bash
if utils::guard "foo"; then return 0; fi
readonly __FOO_SOURCED=1
```

Source-guard для модулей, подключаемых вручную. Возвращает `0`, если модуль **уже**
загружался (нужно сразу сделать `return 0`), и `1`, если ещё не загружался
(можно продолжать выполнение модуля).
Аргумент — имя модуля без частей `__` / `_SOURCED`; внутри оно приводится к верхнему
регистру (`foo` → `__FOO_SOURCED`).

Замечание: модули, загружаемые через `load`, уже защищены от повторной загрузки реестром
`BS_LOADED_MODULES` загрузчика; guard предназначен для файлов, подключаемых
в обход загрузчика.

### utils::has

```bash
if utils::has dnf; then
  utils::quiet dnf check-update
fi
```

Проверяет наличие команды в `PATH`. Возвращает `0`, если команда доступна, иначе `1`.
Заменяет идиому `command -v foo >/dev/null 2>&1`.

### utils::quiet

```bash
if utils::quiet grep -q foo file; then ...; fi
```

Выполняет команду, полностью подавляя stdout и stderr. Код возврата команды сохраняется.
Заменяет идиому `cmd >/dev/null 2>&1`.

### utils::quiet_err

```bash
utils::quiet_err some_cmd
```

Выполняет команду, подавляя только stderr; stdout остаётся видимым. Код возврата команды
сохраняется. Заменяет идиому `cmd 2>/dev/null`.

### utils::ignore

```bash
utils::ignore systemctl stop myservice
```

Выполняет команду с подавленным выводом, игнорируя результат, — всегда возвращает `0`.
Явная замена идиомы `cmd >/dev/null 2>&1 || true`. Использовать только там, где неудача
команды действительно не важна.

### utils::ensure_source

```bash
utils::ensure_source "${ROOT_DIR}/lib/math.sh" add_integers
```

Загружает файл через `source` и проверяет, что требуемая функция появилась в окружении.
Возвращает `0` при успехе и `1` при любой ошибке (файл не найден, source не удался,
функция отсутствует). Диагностика пишется в stderr. Глобальные переменные не изменяются.

### utils::ensure_shell_version

```bash
utils::ensure_shell_version 4
```

Проверяет, что текущий shell (`$SHELL`) имеет мажорную версию не ниже требуемой
(по умолчанию `4`). Поддерживаются `bash` и `zsh`; для старого или неизвестного shell
печатает ошибку в stderr и возвращает `1`. При успехе печатает подтверждение в stdout.

### utils::detect_root

```bash
utils::detect_root
```

Определяет корневую директорию фреймворка и экспортирует её как `FRAMEWORK_ROOT`.
Учитывает заранее заданный `FRAMEWORK_ROOT`, если он указывает на существующую директорию;
иначе вычисляет путь по вызывающему скрипту (разрешая симлинки, поднимаясь из `bin/`).
Сообщает через `log::debug` / `log::info`.

### utils::boot_dir

```bash
utils::boot_dir
```

Устанавливает и экспортирует `BOOT_DIR` — директорию `bootstrap/` фреймворка,
вычисленную относительно самого файла `core/utils.sh`.

## Идиомы тишины

Одна из главных задач `core/utils` — заменить шумные идиомы голого shell с редиректами
на именованные функции, чтобы намерение было видно в месте вызова:

| Голый shell                     | BS                   | Эффект                                            |
|---------------------------------|----------------------|---------------------------------------------------|
| `command -v foo >/dev/null 2>&1` | `utils::has foo`     | Проверка доступности команды                      |
| `cmd >/dev/null 2>&1`           | `utils::quiet cmd`   | Подавить stdout+stderr, код возврата сохраняется  |
| `cmd 2>/dev/null`               | `utils::quiet_err cmd` | Подавить только stderr, код возврата сохраняется |
| `cmd >/dev/null 2>&1 \|\| true` | `utils::ignore cmd`  | Подавить вывод и игнорировать неудачу (всегда `0`) |

Пример — было / стало:

```bash
# голый shell
if command -v dnf >/dev/null 2>&1; then
  dnf check-update >/dev/null 2>&1
fi
systemctl daemon-reload >/dev/null 2>&1 || true

# BS
if utils::has dnf; then
  utils::quiet dnf check-update
fi
utils::ignore systemctl daemon-reload
```
