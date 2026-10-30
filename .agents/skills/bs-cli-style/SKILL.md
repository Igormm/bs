---
name: bs-cli-style
description: Use when styling CLI output, section headers, prompts, error/hint messages or code comments in BS — no `==...==`/`# ====` ASCII-art, framed headers, highlight the main point, bilingual, tty-aware colour, and human-friendly action hints instead of robotic "might need to install package".
type: prompt
whenToUse: When adding or touching user-facing output (headers, summaries, prompts, diagnostics) or section comments; when a message looks robotic, over-long or misses the main point; when choosing how to separate code sections in a module.
---

# BS CLI/вывод стиль — «стильно, модно, молодёжно» / BS output style

Вывод и комментарии делаем **человечными и минималистичными**: никаких ASCII-art
заголовков из `=`, рамки вместо них, главное — подсвечено, остальное — кратко и
двуязычно.

## 1. Заголовки — рамки, не `=`

- Секция в выводе: `bs_log_section "Текст"` (`core/logger.sh`) или `bs_cli_section_header`
  (`bootstrap/cli.sh`) — рамка `╭╮╰╯`, ширина по **символам** (`bs_str_width`).
- Запрещено: `== Текст ==`, `=== Текст ===`, `====…====` в выводе и в комментах.
- Отделитель секций в **коде** — пустая строка + описательный `#`-комментарий, без
  `# ==========================================`.

```sh
# Хорошо / Good:
bs_log_section "Итог / Summary"
# Плохо / Bad:
echo "=== Итог ==="
```

## 2. Подсвечивай главное

- Вердикт/итог — `bs_log_success` (зелёный) / `bs_log_error` (красный), не `bs_log_info`.
- Имена команд, дефолт в промпте — `bs_cli_paint cmd "…"` (cyan).
- Заголовки — жирным (`bs_cli_paint head`).
- Цвет **только на tty** (`bs_log_is_color_enabled` / `bs_cli_color_on`); при пайпе —
  чистый текст, чтобы `grep`/тесты не ломались.

## 3. Двуязычно, RU первым

`текст на русском / English text`. Коротко, без простыни.

## 4. Лови альтернативные действия

- Алиасы: `--version`/`-v`, `-h`/`--help` — принимай как `version`/`help`.
- Промпт: пустой ввод → дефолт; `p|pull`, `g|github`, `l|local`, `a|abort` + полные слова.
- Дефолт в промпте — подсвечен и в скобках: `[p]ull … [a]bort? [p]`.

## 5. Человечные подсказки, не «роботизированно»

- Давай готовое действие, а не констатацию:
  - Плохо: `You might need to install package: foo`.
  - Хорошо: `установите / install it: sudo dnf install foo`.

## 6. Компактность

- Одна короткая строка вместо двух длинных.
- Промпт: `Источник / Source: [p]ull (рекомендуется) · [g]ithub · [l]ocal · [a]bort? [p]`
  вместо перечисления с пояснениями.

## 7. Ширина — по символам

`printf '%-*s'` и `${#s}` считают **байты** и ломают кириллицу. Для рамок и выравнивания —
`bs_str_width` / `bs_str_head`.

## Чек-лист / Checklist

- [ ] Нет `==`/`===`/`# ====` в выводе и комментах.
- [ ] Секции — `bs_log_section`/рамки; в коде — пустая строка + `#`-комментарий.
- [ ] Главное подсвечено (вердикт, команда, дефолт); цвет выключен при пайпе.
- [ ] RU первым, потом EN.
- [ ] `--version`/`-v`, пустой ввод → дефолт и полные слова ловятся.
- [ ] Подсказка даёт действие (`sudo … install`), а не факт.
- [ ] Ширина по символам, не байтам.

## Соседние навыки / Related

- `bs-cli-markdown-style` — простота интерфейса/флагов.
- `bs-cli-noop-output` — рамка «ничего не сделано».
- `bs-cli-flags-style` — структура флагов/подкоманд.
