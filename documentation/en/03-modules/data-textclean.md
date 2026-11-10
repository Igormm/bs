[↑ Documentation index](../README.md)

# Module `textclean` and `bs clean`

Clean text copied from web pages and chat messages before you use it: strip
terminal colour codes, invisible characters, smart quotes, HTML leftovers and
"Copy code" buttons, and get a warning when the text holds a dangerous shell
command. Every cleaning step is a separate **rule** that can be switched on or off.

Tier: **lib** (Bash 4.2+). The kernel (`core/`) is not involved; `bs` only
dispatches the `clean` command to the bash layer.

Sources: [lib/data/textclean.sh](../../../lib/data/textclean.sh) (rules, no UI),
[lib/tui/clean.sh](../../../lib/tui/clean.sh) (window and CLI).

## The command

```bash
bs clean                              # window: paste, toggle rules, Enter
xclip -o | bs clean > clean.txt       # filter: stdin → stdout
bs clean notes.txt                    # filter over files
bs clean --rules ansi,trailing < log.txt
bs clean --unwrap --no-noise --copy < article.txt
```

Without stdin and without files `bs clean` opens a window on the terminal. Paste
the text (Ctrl+Shift+V, Shift+Insert or the mouse; the window uses bracketed
paste, so the text arrives as one piece). The left pane shows the cleaned text,
the right pane lists the rules.

| Key | Action |
|---|---|
| `1`-`9`, `a`-`d` | toggle a rule (the preview updates at once) |
| `Tab` | show the raw text / the cleaned text |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | scroll |
| `Ctrl+U` | clear |
| `s` | save the current rule set as the default |
| `Enter` | copy to the clipboard (OSC 52) and print to stdout |
| `Esc` | quit without output (exit code 1) |

When `danger` finds something, the findings are shown in red and `Enter` has to
be pressed twice. The window draws only on `/dev/tty`, so `bs clean > file`
works: the window is on the screen, the result goes to the file.

In filter mode the result goes to stdout and danger warnings to stderr:
`bs clean: warning: line 3: sudo: sudo rm -rf /tmp/x`.

### Options

| Option | Meaning |
|---|---|
| `-r, --rules LIST` | only these rules (comma separated) |
| `--RULE`, `--no-RULE` | switch one rule on or off: `--unwrap`, `--no-typography` |
| `--all`, `--none` | every rule on / off (combine: `--none --trailing`) |
| `-l, --list` | rules with their state and description |
| `-w, --window` / `-f, --filter` | force the mode (`--window` pre-fills stdin) |
| `-c, --copy` | also copy the result in filter mode |
| `--no-copy` | do not copy in the window |
| `--tab-width N` | tab stop for `tabs` (default 4) |
| `--unwrap-min N` | shortest line `unwrap` joins (default 50) |
| `--guillemets` | `typography` also turns `«»` into `"` |
| `--noise RE` | one more noise pattern (ERE over the whole trimmed line) |
| `--no-config` | ignore the config files |
| `--strict` | exit code 3 when `danger` finds something |
| `-q, --quiet` | no danger warnings on stderr |

Exit codes: 0 ok, 1 window cancelled, 2 usage error, 3 danger with `--strict`.

## Rules

Rules run in this order over the whole text:

| Key | Rule | Default | What it does |
|---|---|---|---|
| 1 | `ansi` | on | ANSI escape codes (CSI, OSC, DCS), backspace overstrike, control characters; CRLF → LF; a line with CR keeps what the terminal showed |
| 2 | `tags` | off | HTML tags and comments; `<br>`, `</p>`, `</div>`, `</li>` → line break, `<li>` → `- ` |
| 3 | `entities` | on | `&amp;` `&lt;` `&nbsp;` `&mdash;` …, `&#39;`, `&#x2014;`; one pass, so `&amp;lt;` → `&lt;` |
| 4 | `invisible` | on | zero-width characters, BOM, soft hyphen, bidi controls (Trojan Source) are removed; NBSP and other Unicode spaces → space |
| 5 | `markdown` | off | `\_` `\*` `\#` … unescaped; ```` ``` ```` / `~~~` fence lines removed |
| 6 | `typography` | on | `“ ” „` → `"`, `‘ ’` → `'`, `— – −` → `-`, `…` → `...`, `•` → `-`; `«»` only with `--guillemets` |
| 7 | `tabs` | off | tabs → spaces up to the next tab stop |
| 8 | `noise` | on | lines that are only `Copy`, `Copy code`, `Click to expand`, `Show more`, `Скопировать`, `Показать ещё` …, and a language label (`bash`) right before such a line |
| 9 | `trailing` | on | spaces at line ends |
| a | `dedent` | off | the indentation common to all non-blank lines |
| b | `unwrap` | off | join hard-wrapped paragraphs; lines shorter than `--unwrap-min` (commands) stay, as do lists, headings, quotes, tables and code |
| c | `blank` | on | blank runs → one blank line, none at the start and the end |
| d | `danger` | on | does not change the text: warns about `sudo`, `rm -r`, `curl … \| sh`, `mkfs`, `dd of=/dev/…`, `chmod 777`, fork bomb, `shutdown`, `git push --force`, `eval`, hidden Unicode … |

## Configuration

`${XDG_CONFIG_HOME:-~/.config}/bs/clean/` (or `TEXTCLEAN_CONFIG_DIR`):

- `rules` — one `name=on|off` per line; `s` in the window writes it.
- `noise` — one ERE per line, added to the built-in noise patterns.

```text
# ~/.config/bs/clean/rules
unwrap=on
typography=off
```

```text
# ~/.config/bs/clean/noise
Sponsored
Advertisement
\[[0-9]+ more lines\]
```

Order of precedence: built-in defaults → config files → command line.

## Library API

```bash
#!/usr/bin/env bs

load "lib/data/textclean"

textclean::reset                  # defaults
textclean::enable unwrap tabs     # LIB_ERROR_INVALID_INPUT for an unknown name
textclean::disable typography
textclean::toggle noise
textclean::only "ansi,trailing"   # only these
textclean::is_enabled blank && echo on
textclean::enabled                # ansi,trailing
textclean::rules                  # names in run order
textclean::describe unwrap ru     # description, en or ru
textclean::config::load           # rules + noise files
textclean::config::save           # rules file, path in REPLY

textclean::string "${text}"       # clean a string → stdout
textclean::filter < page.txt      # stdin → stdout

TEXTCLEAN_TEXT="${text}"          # or work on the buffer directly
textclean::process                # every enabled rule; danger → TEXTCLEAN_DANGER
textclean::rule::entities         # one rule over TEXTCLEAN_TEXT
textclean::danger::scan           # "line<TAB>reason<TAB>text" in TEXTCLEAN_DANGER

textclean::osc52 "${text}"        # OSC 52 sequence in REPLY (tmux/screen aware)
textclean::copy "${text}"         # write it to /dev/tty
```

Settings: `TEXTCLEAN_TAB_WIDTH`, `TEXTCLEAN_UNWRAP_MIN`, `TEXTCLEAN_GUILLEMETS`,
`TEXTCLEAN_NOISE` (array of ERE), `TEXTCLEAN_DANGER_RULES` (array of
`reason<TAB>ERE`), `TEXTCLEAN_CONFIG_DIR`.

The rules work on bytes (UTF-8 literals are written as `\x` escapes), so they
give the same result in the C and UTF-8 locales.

## Clipboard

The copy uses OSC 52: the terminal itself puts the text into the clipboard, so
it works over SSH and needs no `xclip`/`pbcopy`. Inside tmux the sequence is
wrapped for passthrough (tmux needs `set -g set-clipboard on` or
`allow-passthrough on`). Terminals that support OSC 52: kitty, WezTerm, Alacritty,
foot, iTerm2, Windows Terminal, recent xterm and GNOME Terminal (VTE 0.76+).

## Limits

- `danger` is a heuristic warning, not a sandbox: it reads lines, not shell syntax.
- `tags` is off by default: it would also remove `<stdin>` or `<file>` from
  ordinary text.
- `unwrap` decides by line length; set `--unwrap-min` to your source's wrap width.

## Tests

[tests/unit/testtextcleanunit.sh](../../../tests/unit/testtextcleanunit.sh) — every rule, the
pipeline, config files, OSC 52 and the CLI.
