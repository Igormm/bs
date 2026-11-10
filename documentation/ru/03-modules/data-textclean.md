[↑ Оглавление документации](../README.md)

# Модуль `textclean` и `bs clean`

Очистка текста, скопированного из веба и сообщений чатов, перед использованием:
убрать цветовые коды терминала, невидимые символы, «умные» кавычки, остатки
HTML и кнопки «Copy code», а также предупредить, если в тексте есть опасная
команда. Каждый шаг очистки — отдельное **правило**, которое можно включить
или выключить.

Уровень: **lib** (Bash 4.2+). Ядро (`core/`) не затронуто; `bs` лишь передаёт
команду `clean` bash-слою.

Исходники: [lib/data/textclean.sh](../../../lib/data/textclean.sh) (правила, без UI),
[lib/tui/clean.sh](../../../lib/tui/clean.sh) (окно и CLI).

## Команда

```bash
bs clean                              # окно: вставить, переключить правила, Enter
xclip -o | bs clean > clean.txt       # фильтр: stdin → stdout
bs clean notes.txt                    # фильтр по файлам
bs clean --rules ansi,trailing < log.txt
bs clean --unwrap --no-noise --copy < article.txt
```

Без stdin и без файлов `bs clean` открывает окно в терминале. Вставьте текст
(Ctrl+Shift+V, Shift+Insert или мышью; окно включает bracketed paste, поэтому
текст приходит целиком). Слева очищенный текст, справа список правил.

| Клавиша | Действие |
|---|---|
| `1`-`9`, `a`-`d` | переключить правило (предпросмотр обновляется сразу) |
| `Tab` | показать исходный / очищенный текст |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | прокрутка |
| `Ctrl+U` | очистить |
| `s` | сохранить текущий набор правил по умолчанию |
| `Enter` | скопировать в буфер обмена (OSC 52) и напечатать в stdout |
| `Esc` | выйти без вывода (код 1) |

Если `danger` что-то нашёл, находки показаны красным и `Enter` нужно нажать
дважды. Окно рисуется только в `/dev/tty`, поэтому `bs clean > file` работает:
окно на экране, результат в файле.

В режиме фильтра результат идёт в stdout, предупреждения danger — в stderr:
`bs clean: warning: line 3: sudo: sudo rm -rf /tmp/x`.

### Опции

| Опция | Значение |
|---|---|
| `-r, --rules СПИСОК` | только эти правила (через запятую) |
| `--ПРАВИЛО`, `--no-ПРАВИЛО` | включить или выключить одно правило: `--unwrap`, `--no-typography` |
| `--all`, `--none` | все правила вкл / выкл (можно сочетать: `--none --trailing`) |
| `-l, --list` | правила с состоянием и описанием |
| `-w, --window` / `-f, --filter` | задать режим (`--window` подставляет stdin) |
| `-p, --paste` | взять на вход системный буфер обмена (см. «Буфер обмена») |
| `-c, --copy` | в режиме фильтра тоже копировать результат |
| `--no-copy` | не копировать в окне |
| `--tab-width N` | шаг табуляции для `tabs` (по умолчанию 4) |
| `--unwrap-min N` | самая короткая строка, которую склеивает `unwrap` (по умолчанию 50) |
| `--guillemets` | `typography` меняет и `«»` на `"` |
| `--noise RE` | ещё один шаблон шума (ERE по всей обрезанной строке) |
| `--no-config` | не читать файлы настроек |
| `--strict` | код выхода 3, если `danger` что-то нашёл |
| `-q, --quiet` | без предупреждений danger в stderr |

Коды выхода: 0 — успех, 1 — окно закрыто без результата, 2 — ошибка
аргументов, 3 — danger при `--strict`.

## Правила

Правила выполняются в этом порядке над всем текстом:

| Клавиша | Правило | По умолчанию | Что делает |
|---|---|---|---|
| 1 | `ansi` | вкл | ANSI-последовательности (CSI, OSC, DCS), забой с наложением, управляющие символы; CRLF → LF; у строки с CR остаётся то, что показал терминал |
| 2 | `tags` | выкл | HTML-теги и комментарии; `<br>`, `</p>`, `</div>`, `</li>` → перевод строки, `<li>` → `- ` |
| 3 | `entities` | вкл | `&amp;` `&lt;` `&nbsp;` `&mdash;` …, `&#39;`, `&#x2014;`; за один проход, поэтому `&amp;lt;` → `&lt;` |
| 4 | `invisible` | вкл | символы нулевой ширины, BOM, мягкий перенос, bidi-управление (Trojan Source) удаляются; NBSP и прочие Unicode-пробелы → пробел |
| 5 | `markdown` | выкл | снимается экранирование `\_` `\*` `\#` …; строки ```` ``` ```` / `~~~` удаляются |
| 6 | `typography` | вкл | `“ ” „` → `"`, `‘ ’` → `'`, `— – −` → `-`, `…` → `...`, `•` → `-`; `«»` только с `--guillemets` |
| 7 | `tabs` | выкл | табуляция → пробелы до следующего шага |
| 8 | `noise` | вкл | строки, состоящие только из `Copy`, `Copy code`, `Click to expand`, `Show more`, `Скопировать`, `Показать ещё` …, и метка языка (`bash`) прямо перед такой строкой |
| 9 | `trailing` | вкл | пробелы в конце строк |
| a | `dedent` | выкл | общий для всех непустых строк отступ |
| b | `unwrap` | выкл | склеить разорванные абзацы; строки короче `--unwrap-min` (команды) остаются, как и списки, заголовки, цитаты, таблицы и код |
| c | `blank` | вкл | серии пустых строк → одна, по краям пустых строк нет |
| d | `danger` | вкл | текст не меняет: предупреждает о `sudo`, `rm -r`, `curl … \| sh`, `mkfs`, `dd of=/dev/…`, `chmod 777`, fork bomb, `shutdown`, `git push --force`, `eval`, скрытом Unicode … |

## Настройки

`${XDG_CONFIG_HOME:-~/.config}/bs/clean/` (или `TEXTCLEAN_CONFIG_DIR`):

- `rules` — по строке `имя=on|off`; клавиша `s` в окне записывает этот файл.
- `noise` — по одному ERE в строке, добавляются к встроенным шаблонам шума.

```text
# ~/.config/bs/clean/rules
unwrap=on
typography=off
```

```text
# ~/.config/bs/clean/noise
Реклама
Sponsored
\[[0-9]+ more lines\]
```

Приоритет: встроенные значения → файлы настроек → командная строка.

## API библиотеки

```bash
#!/usr/bin/env bs

load "lib/data/textclean"

textclean::reset                  # значения по умолчанию
textclean::enable unwrap tabs     # LIB_ERROR_INVALID_INPUT для неизвестного имени
textclean::disable typography
textclean::toggle noise
textclean::only "ansi,trailing"   # только эти
textclean::is_enabled blank && echo on
textclean::enabled                # ansi,trailing
textclean::rules                  # имена по порядку выполнения
textclean::describe unwrap ru     # описание, en или ru
textclean::config::load           # файлы rules и noise
textclean::config::save           # файл rules, путь в REPLY

textclean::string "${text}"       # очистить строку → stdout
textclean::filter < page.txt      # stdin → stdout

TEXTCLEAN_TEXT="${text}"          # или работать с буфером напрямую
textclean::process                # все включённые правила; danger → TEXTCLEAN_DANGER
textclean::rule::entities         # одно правило над TEXTCLEAN_TEXT
textclean::danger::scan           # "строка<TAB>причина<TAB>текст" в TEXTCLEAN_DANGER

textclean::osc52 "${text}"        # последовательность OSC 52 в REPLY (учитывает tmux/screen)
textclean::copy "${text}"         # записать её в /dev/tty
```

Настройки: `TEXTCLEAN_TAB_WIDTH`, `TEXTCLEAN_UNWRAP_MIN`, `TEXTCLEAN_GUILLEMETS`,
`TEXTCLEAN_NOISE` (массив ERE), `TEXTCLEAN_DANGER_RULES` (массив
`причина<TAB>ERE`), `TEXTCLEAN_CONFIG_DIR`.

Правила работают по байтам (UTF-8 записан `\x`-escape), поэтому результат
одинаков в локалях C и UTF-8.

## Буфер обмена

Копирование идёт через OSC 52: текст в буфер обмена кладёт сам терминал,
поэтому это работает и по SSH и не требует `xclip`/`pbcopy`. Внутри tmux
последовательность оборачивается для passthrough (tmux нужен
`set -g set-clipboard on` или `allow-passthrough on`). OSC 52 поддерживают
kitty, WezTerm, Alacritty, foot, iTerm2, Windows Terminal, свежие xterm и
GNOME Terminal (VTE 0.76+).

Для чтения буфера (`bs clean --paste`, `textclean::paste`) программа нужна:
терминалы не отдают буфер через OSC 52. Программы перебираются по порядку
через `deps::has` фреймворка (они же `@optdeps` модуля): `wl-paste`, `xclip`,
`xsel`, `pbpaste`, `termux-clipboard-get`, `powershell.exe` (WSL).
Установленная, но упавшая программа (нет дисплея) пропускается. Если не
сработала ни одна, `bs clean --paste` выходит с кодом 2 и подсказывает, что
работает без неё:

```text
bs clean: --paste: no clipboard reader found (wl-paste xclip xsel pbpaste termux-clipboard-get powershell.exe).
  Вставьте текст в окно: bs clean   или подайте его на вход: bs clean < file
```

`textclean::paste` возвращает `LIB_ERROR_DEPENDENCY_MISSING`, если программ нет,
и `LIB_ERROR_DEPENDENCY`, если все установленные упали; `TEXTCLEAN_PASTE_TOOL` —
имя сработавшей программы. Список — `TEXTCLEAN_PASTE_TOOLS`.

## Ограничения

- `danger` — эвристическое предупреждение, а не песочница: он читает строки, а
  не синтаксис оболочки.
- `tags` по умолчанию выключено: оно удалило бы и `<stdin>` или `<file>` из
  обычного текста.
- `unwrap` решает по длине строки; задайте `--unwrap-min` по ширине переноса
  источника.

## Тесты

[tests/unit/testtextcleanunit.sh](../../../tests/unit/testtextcleanunit.sh) — каждое правило,
конвейер, файлы настроек, OSC 52 и CLI.
