---
name: bs-logging
description: Use when writing or reviewing logging in BS — choosing log level and stream, the tier-specific names (bs_log_* in posix, log::* in bash4/zsh), section headers, and the traps (stdout pollution, tty colour, character widths)
type: prompt
whenToUse: When adding/editing log calls, section headers, verdict or diagnostic output in any module or script; when a log line pollutes a function result; when output misaligns or loses colour in a pipe
tier: both
---

# Логирование по ярусам / Logging by tier

Один логгер — `core/logger.sh`. Имена зависят от **яруса файла**: правило §2 гайда,
детали вывода — навык `bs-cli-style` и `bs-posix-output` (§4). Доктрина ярусов —
`bs-shell-portability`.

| Ярус файла | Имена логгера |
| --- | --- |
| `@shell posix` (core/, bootstrap/, install/, posix-скрипты) | настоящие `bs_log_*` |
| `@shell bash4` (`#!/usr/bin/env bs`, lib/, bash-скрипты) и zsh | алиасы `log::*` |

`bs_log_*` в bash4-коде не идиоматичен; `log::*` в posix-коде не существует.
Алиасы создаёт `bs_shell_alias` в конце `core/logger.sh` (bash и zsh).

## Виды логирования (уровни)

Уровни по возрастанию: `TRACE < DEBUG < INFO < SUCCESS < WARN < ERROR < FATAL`;
показ фильтруется `BS_LOG_LEVEL` (по умолчанию `INFO`, значит SUCCESS и выше видимы,
а TRACE/DEBUG скрыты). Уровень проверяется ДО форматирования.

| Вызов | Поток | Назначение |
| --- | --- | --- |
| `log::trace` / `bs_log_trace` | stdout | трассировка алгоритма (по `BS_LOG_LEVEL=TRACE`) |
| `log::debug` / `bs_log_debug` | stdout | отладка |
| `log::info` / `bs_log_info` | stdout | данные/прогресс/обычные строки |
| `log::success` / `bs_log_success` | stdout | вердикт «хорошо» (зелёный) |
| `log::warn` / `bs_log_warn` | **stderr** | предупреждение |
| `log::error` / `bs_log_error` | **stderr** | ошибка |
| `log::fatal` / `bs_log_fatal` | **stderr** | фатально; ВОЗВРАЩАЕТ `E_ERROR`, сам не завершает — решение о выходе за вызывающим |

Структурные:

| Вызов | Что даёт |
| --- | --- |
| `log::section "Итог / Summary"` | рамка `╭╮╰╯` **без** префикса лога (прямой printf), ширина по символам (`bs_str_width`), цвет только на tty |
| `log::header "Текст"` | рамка через `log::info` (с префиксом) |
| `log::list "а" "б"` | маркированный список (`•` на tty, `*` без) |
| `log::table "строка" …` | строки с отступом |
| `log::progress …` | строка прогресса |
| `log::clear_line` | стереть строку |
| `log::print` | алиас `log::info` |

Форматы: `BS_LOG_FORMAT=text|json|structured`, цвет `BS_LOG_COLOR` (авто на tty),
метка `BS_LOG_TIMESTAMP`.

## Правила (проверены прогоном, встречались в проекте)

1. **stdout функции — её результат.** `log::info/debug/trace/success/print` пишут в
   stdout: вызов такого лога внутри функции, чей stdout — значение (и особенно в
   `$(...)`), портит результат. Диагностику в возвращающей функции — только
   `log::warn`/`log::error` (stderr) или `printf '%s\n' "…" >&2`.
2. **Вердикты — success/error, не info.** `log::success` для «сделано», `log::error`
   для провала; `log::info` для фактов. Итог подсвечен, остальное кратко.
3. **Двуязычно, RU первым** в пользовательском выводе: `log::section "Готово / Done"`.
4. **Цвет только на tty** (`bs_log_is_color_enabled`): при пайпе вывод чистый, чтобы
   grep/тесты не ломались.
5. **Ширина по символам**: `log::section`/`log::header` меряют `bs_str_width`, не
   `${#s}` — кириллица не рвёт рамку.
6. **До логгера** (модули `quiet`/`data`/`fmt`/`prereq`) и в коде, который должен
   работать без него: `printf '%s\n' "функция: что не так: значение" >&2` (§12.9).
7. **«Нечего делать» — не `log::error`**: framed-бокс и return 0 (навык
   `bs-cli-noop-output`).
8. **`log::fatal` не завершает скрипт** — он возвращает код; выход — через
   `error::exit`/`bs_error_exit`, чтобы отработала очистка.

## Скелет

```bash
# bash4: log::*  / posix: bs_log_*
log::section "Проверка / Check"
log::info "  файл / file: ${path}"
log::success "готово / done"
log::error "не найден / not found: ${name}"   # stderr
```

## Типичные ошибки

| Ошибка | Правильно |
| --- | --- |
| `bs_log_info` в bash4-коде | `log::info` |
| `log::*` в posix-коде | `bs_log_*` |
| `log::info` внутри функции, возвращающей значение в stdout | `log::warn`/`log::error` или stderr |
| `log::info "всё сделано"` (вердикт) | `log::success "всё сделано / done"` |
| `== Готово ==` вместо рамки | `log::section "Готово / Done"` |
| цвет в пайпе | логгер сам выключает на не-tty; свои цвета — `printf '\033[1;34m'` |
| рамка по `${#s}` с кириллицей | `bs_str_width` (логгер уже так делает) |
