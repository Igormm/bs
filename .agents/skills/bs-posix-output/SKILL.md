---
name: bs-posix-output
description: Use when writing or reviewing input/output of @shell posix code (core/, bootstrap/, install/, posix entry points) — returning values, diagnostics, user-facing CLI output, ANSI, and the per-shell output traps (zsh splitting, byte widths, printf padding)
type: prompt
whenToUse: When a posix-tier function returns values or prints anything; when styling CLI/demo output in posix code; when output breaks in dash/zsh/mksh or misaligns on Cyrillic; when choosing between stdout, an output variable and the logger
tier: posix
---

# Вывод и ввод в ярусе `@shell posix` / I/O in the posix tier

Правила яруса — глава 12 `documentation/{ru,en}/code-style-guide.md` (§12.8 значения,
§12.9 ошибки/сообщения); стиль пользовательского вывода — навык `bs-cli-style`;
«нечего делать» — `bs-cli-noop-output`; ANSI — `bs-check-ansi`. Здесь — выжимка
для кода, который работает в bash, zsh, dash, busybox ash, ksh93, mksh.
Имена настоящие (`bs_*`); псевдонимы `log::*`/`io::streams::*` существуют только
в bash/zsh и в posix-коде не используются.

## 1. Три вида вывода — не смешивать

| Вид | Куда | Чем |
| --- | --- | --- |
| Результат функции | stdout или выходная переменная | `printf '%s\n'`, §12.8 |
| Диагностика (ошибка/предупреждение) | stderr | `bs_log_error` / `bs_log_warn`; до логгера — `printf '%s\n' "…" >&2` |
| Пользовательский вывод (CLI, демо) | stdout | `bs_log_section` / `bs_log_info` / `bs_log_success` / `bs_log_list` / `bs_log_table` |

**Функция, чей stdout — результат, не печатает ничего лишнего.** `bs_log_info`,
`bs_log_debug`, `bs_log_trace`, `bs_log_success` пишут в STDOUT — вызов такого
`bs_log_*` внутри возвращающей функции (особенно в `$(...)`) портит результат.
Диагностика в ней — только `bs_log_warn`/`bs_log_error` (stderr).

## 2. Возврат значений (§12.8)

| Что нужно | Как | Образец |
| --- | --- | --- |
| Да/нет | только статус, без вывода | `bs_utils_has`, `bs_arr_contains` |
| Одно значение | stdout: `printf '%s\n' "$v"`; статус 1 — «нет такого» | `bs_arr_get`, `bs_map_get` |
| Горячий путь | выходная переменная (`$(...)` = форк) | `bs_guard__var`, `bs_log_replace_all` |
| По желанию вызывающего | необязательный параметр «имя переменной»; пусто — stdout | `bs_arr_pop имя [переменная]` (`bs_data_ret`) |
| Много значений | массив слоя данных, имя передаёт вызывающий | `bs_utils_split массив строка разделители` |

- Мутирующие функции (`bs_arr_pop`, `bs_obj_new`, `bs_cache_put`…) **нельзя** звать
  как `$(...)` — мутация останется в подоболочке; в doc-комментарии так и пишут.
- `$(...)` срезает завершающие переводы строки — значение с ними возвращают только
  в переменную.
- Имя выходной переменной проверяют до eval (`bs_data_ret` → код 2).
- Коды: 0 успех; 1 «нет/ложь»; 2 плохое имя/аргумент; дальше — `LIB_ERROR_*`.
  Последняя команда = статус функции: заканчивайте явным `return`.

## 3. Диагностика и ошибки (§12.9)

- После логгера: `bs_log_error "…"` / `bs_log_warn "…"` (stderr). До логгера или
  без него (`quiet`, `data`, `fmt`, `prereq`): `printf '%s\n' "bs_module: что не так: значение" >&2`.
- Формат сообщения: `имя_функции: что не так: значение` — стека вызовов в posix нет.
- Функции возвращают код, не `exit`; выход точки входа — `bs_exit`/`bs_error_exit`
  (с очисткой). Очистка — `bs_cleanup_add функция`, не trap на месте; в модуле
  регистрация защищена `if command -v bs_cleanup_add >/dev/null 2>&1`.
- «Нечего делать» — не ERROR: return 0 и framed-бокс (навык `bs-cli-noop-output`).
- `${1:?}` не завершает mksh — для пользовательского входа `[ -n "${1-}" ] || return 2`.

## 4. Пользовательский вывод: стиль проекта на posix-именах

```sh
bs_log_section "Итог / Summary"          # рамка ╭╮╰╯, БЕЗ префикса лога, цвет только на tty
bs_log_info "  записей / entries: 3"     # данные — info
bs_log_success "кеш очищен / cache cleared"   # вердикт — success (зелёный), не info
bs_log_error "запись не найдена / entry not found"  # провал — error (красный, stderr)
bs_log_list "первый / first" "второй / second"      # • на tty, * без цвета
bs_log_table "key=value" "key2=value2"              # строки с отступом
```

- Заголовки секций — **рамки** `bs_log_section`, никогда `== Текст ==`/`====…====`
  (и в выводе, и в комментариях кода). Ширина — по **символам** (`bs_str_width`),
  не по байтам: кириллица иначе ломает рамку.
- Двуязычно, **RU первым**: `текст / text`. Коротко, главное — подсвечено.
- Цвет — только на tty: логгер сам проверяет (`bs_log_is_color_enabled`); при пайпе
  вывод чистый, чтобы grep/тесты не ломались. Свои цвета — `printf '\033[1;34m'`,
  не `$'\033'` (ANSI-C quoting — bash) и не литерал `\033` в `printf %s` (см. `bs-check-ansi`).
- Паддинг рамок/колонок — по символам; `printf '%-*s'` паддит по БАЙТАМ в dash/ash —
  для кириллицы считать ширину `bs_str_width` и добивать пробелами вручную
  (образец: noop-бокс `bs_cache_main`, `bs-cli-noop-output`).
- Подсказки — готовое действие («далее / next: bs cache put KEY VALUE»), не
  робот-констатация («might need to install package»).
- Данные для машин (манифест, значения) — голый `printf '%s\n'`, без рамок и цвета;
  рамки и цвет — только человекочитаемый слой.

## 5. Ввод и разбор

- `IFS= read -r line` — IFS только на команду read, не глобально; сбой read (EOF,
  сигнал) — не валидный ввод: обрабатывать отдельно (ловушка `read … || k=""` →
  фантомный ENTER в TUI).
- zsh **не делит** `$var` на слова: `for w in $list` — одна итерация. Разбор —
  `bs_utils_split массив строка разделители`, `bs_arr_from_lines`, или
  `eval "$(bs_arr_to_args имя)"` (каждый элемент через `bs_quote`).
- IFS точек входа = newline+tab: `"$*"` склеивает слова переводом строки —
  соединять через `bs_str_join`/`bs_log_join_words`, не `"$*"`.
- Недоверенные данные — `printf '%s' "$data"`, никогда форматом (`printf "$data"`)
  и никогда `echo -e`/`echo "$data"` (echo по-разному понимает `-n`/`-e`/`\`).
- `${#s}` считает БАЙТЫ в dash/mksh и символы в bash/zsh/ksh — ширина/обрезка
  только `bs_str_width`/`bs_str_head`.

## 6. Скелет точки входа

Скрипт под `#!/usr/bin/env bs` (ядро уже загружено интерпретатором):

```sh
#!/usr/bin/env bs
# shellcheck shell=bash
strict::enable                       # флаги + IFS + ловушки + очистка (core/strict.sh)
bs_log_section "Демо / Demo"
bs_log_info "  значение / value: 42"
bs_log_success "готово / done"
```

Posix-файл, подключаемый напрямую (`. файл` из любой оболочки реестра):
логгер уже загружен ядром — те же `bs_log_*` без всякого подключения. До ядра
(pre-kernel пролог) — только `printf '%s\n' "…" >&2`, никаких `bs_log_*`.
Образец posix-вывода: `bootstrap/cli.sh` (`bs_log_section`, `bs_log_info`,
`bs_log_success`). Скрипты `example_core/*.sh` — ярус bash4, там имена `log::*`
(см. скилл `bs-logging`): результат тот же набор рамок/вердиктов, но с `log::section`.

## Частые ошибки (все встречались в проекте)

| Ошибка | Правильно |
| --- | --- |
| `bs_log_info` внутри функции, возвращающей значение в stdout | `bs_log_warn`/`bs_log_error` или stderr |
| `v=$(bs_arr_pop a)` — мутация потерялась | `bs_arr_pop a v` |
| `== Итог ==` / `# =====` | `bs_log_section "Итог / Summary"` |
| рамка по `${#s}` / `printf '%-*s'` с кириллицей | `bs_str_width` + ручные пробелы |
| `for w in $list` в zsh | `bs_utils_split` / `bs_arr_to_args` |
| `echo -e "$msg"` / `printf "$data"` | `printf '%s\n' "$msg"` / `printf '%s' "$data"` |
| `$'\033[31m'` в posix-файле | `printf '\033[31m'` |
| «ничего не найдено» как ERROR + exit 1 | noop-бокс + return 0 |
| EN-first или одноязычный вывод | «RU / EN», RU первым |
