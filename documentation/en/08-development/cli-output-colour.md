[↑ Developer guide](README.md)

# Colouring CLI output

How to find the places where BS prints text and make the right parts coloured
without guessing. The short version: colour is a **role**, not decoration, and
the terminal check is made **once**, not at the point where a string is built.

## 1. Find the output sites

The inventory script lists every direct output command (`printf`, `echo`,
`print`, `printn`, `eprint`, `eprintn`, `tty_print`) and separates the ones that
already use a helper from the plain ones:

```bash
sh scripts/check_output_color.sh                       # bootstrap/cli.sh + lib/
sh scripts/check_output_color.sh --list                # every plain command
sh scripts/check_output_color.sh --list bootstrap/cli.sh
sh scripts/check_output_color.sh --all lib             # include the engines
```

A line is counted as coloured when the logical command (backslash
continuations are joined) mentions `bs_cli_paint`, `bs_log_*`,
`presentation::*`, `tui::*`, `wiz::*`, a `COLOR_`/`PRESENTATION_*` constant,
`bs_error_exit`/`bs_cli_die`, or contains an ANSI escape. `printf -v` is an
assignment, not output, and is counted separately. Heredoc bodies are skipped.

The script is deliberately an **inventory, not a gate**: help text and data
output are plain on purpose, and only a human can tell them from a missed
label. For a narrower sweep use the same primitives with ripgrep:

```bash
rg -n '^[[:space:]]*(printf|echo|print|printn|eprint|eprintn|tty_print)[[:space:]]' bootstrap lib
```

## 2. Decide what becomes coloured

Colour the **value** (or the verdict), keep the label readable:

| Colour | Examples |
| --- | --- |
| green | a healthy state, a local install kind, a matching commit |
| yellow | a warning, a system install, an updated commit that differs |
| red | an error, a corrupt manifest |
| cyan/magenta | paths, commits, custom install kinds |
| none | help/usage text, `env`-style machine output, data written to a file |

Do not colour a whole line "for beauty": boxes, tables and logs compute width
from characters, and ANSI escapes would break them.

## 3. Apply it with the existing helper

In the pre-kernel POSIX part of the CLI (`bootstrap/cli.sh`), wrap the value:

```bash
printf '  %-10s %s\n' "path:" "$(bs_cli_paint path "${__bs_cli_isrc:-?}")"
```

`bs_cli_paint <kind> <text>` lives next to `bs_cli_color_on`
(`bootstrap/cli.sh:262`, paint at `:284`); the kind table is its `case` at
`:289` — `local`, `system`, `custom`, `checkout`, `path`, `commit`,
`commit_same`, `commit_diff`, `bad`, `warn`. Add a new kind there instead of
writing raw escapes at the call site.

In `lib/`:

- messages go through `bs_log_info|warn|error|success` (colour, level and
  format are controlled by the logger);
- a single value by hand uses `presentation::colorize` with a
  `PRESENTATION_COLOR_*` constant (`lib/ui/presentation.sh:183`);
- TUI code uses `tui::`/`wiz::` primitives, not escapes of its own.

Raw `\033` belongs only in the abstraction layer. Run the ANSI checker after
touching escapes: `bash .agents/skills/bs-check-ansi/scripts/check_ansi.sh`.

## 4. Respect the gate

The gate is shared and already implemented — do not re-test the terminal in
your own function:

- `NO_COLOR` (set and non-empty) turns colour off;
- `BS_LOG_COLOR=always|never|auto` overrides the terminal check;
- `auto` (the default) colours only when stdout is a terminal.

### The `$(...)` trap

`$(bs_cli_paint …)` runs in a command substitution, where stdout is a **pipe**,
so a `[ -t 1 ]` check inside the substitution is always false. That is why
`bs_cli_color_on` uses `__bs_cli_color_tty`, recorded once when
`bootstrap/cli.sh` is loaded, before any substitution. Keep this rule for new
helpers: decide the tty state at load time and consult the saved value.

Boxes and frames that measure text must be built without colour: capture the
block with `BS_CLI_INFO_NO_COLOR=1` (see `bootstrap/cli.sh:910`) and measure the
plain string with `bs_str_width`.

## 5. Verify both worlds

```bash
# a terminal: ANSI must be present
script -q -c './bs version --full' /dev/null | cat -v

# a pipe: ANSI must be absent
./bs version --full | cat -v

# explicit gates
NO_COLOR=1 ./bs version --full | cat -v
BS_LOG_COLOR=always ./bs version --full | cat -v   # colour even in a pipe
```

Unit tests use the same idea: run the command under `script` for the coloured
case and through a plain pipe for the colourless one; skip the pty case
honestly when `script` cannot create a pty (see
`tests/unit/testuninstallsafetyunit.sh`, the `version --full` section).
