# Nushell

[Nushell](https://www.nushell.sh/) is a shell built around **typed, structured
data**. Commands pass records, tables, and lists — not raw text — so most
`sed`/`awk`/`cut` munging disappears, and a different set of rules applies.

Rules below are distilled from the official [Nushell Book](https://www.nushell.sh/book/)
and cited per section. Snippets are minimal and paraphrased; consult the linked
pages for detail. Guidance targets **Nushell 0.114** (the current release at time
of writing) — see [Version stability](#version-stability), which is itself a rule.

## The mental model: parse time, then run time

Nushell parses the **entire** script to an intermediate representation first,
then evaluates it. There is no `eval`, and nothing you compute at run time can
change what was already parsed.
([thinking in nu](https://www.nushell.sh/book/thinking_in_nu.html),
[how nushell code gets run](https://www.nushell.sh/book/how_nushell_code_gets_run.html))

1. **`source`, `use`, and `overlay use` need a parse-time-constant path.** Their
   argument is resolved during parsing, before any `let`/`$env` exists. Use a
   `const`:

   ```nu
   const mods = ($nu.default-config-dir | path join "my-mods")
   use $"($mods)/utils.nu"
   ```

2. **A runtime `if (... | path exists)` guard cannot rescue a parse-time
   `source`.** The path is resolved at parse time regardless of the `if`, so a
   missing file still aborts startup with `sourced_file_not_found`. Generate the
   file *earlier* (in `env.nu`, before `config.nu` is parsed) instead. This exact
   bug and its fix are demonstrated at runtime in
   [`tests/nushell-startup-demo.sh`](../tests/nushell-startup-demo.sh).

3. **Do not build code as a string and `source` it in the same file.** It cannot
   exist at parse time. Only a small set of pure commands (e.g. `path join` on
   `$nu.*` constants) can produce a parse-time constant.

## Structured data, not text

- **Pipelines carry typed values.** Reach for `get`/`select`/`where`/`update`
  on columns, not text tools. There is no implicit whitespace word-splitting.
  ([coming from bash](https://www.nushell.sh/book/coming_from_bash.html))
- **Write files with `save`, not `>`.** In Nushell `>` is the greater-than
  operator, not redirection.
  ([thinking in nu](https://www.nushell.sh/book/thinking_in_nu.html))

  ```nu
  "hello" | save output.txt        # not:  echo "hello" > output.txt
  ```

- **`get` unwraps values; `select` keeps a table.** Choosing wrong changes the
  shape of everything downstream.
  ([working with tables](https://www.nushell.sh/book/working_with_tables.html))

  ```nu
  ls | get name          # a list of names
  ls | select name size  # a two-column table
  ```

- **Edits are non-mutating.** `update`/`insert`/`upsert` return new data; use
  `upsert` when a column may or may not already exist.
- **Convert types deliberately** with `into`/`from`; loaded data is often
  strings. ([loading data](https://www.nushell.sh/book/loading_data.html))

  ```nu
  open people.txt | lines | split column "|" first last job | str trim
  ```

## Variables and immutability

Prefer immutable bindings; they are what make Nushell's functional and parallel
constructs safe. ([variables](https://www.nushell.sh/book/variables.html))

- **`let` by default.** Shadow in an inner scope rather than mutating.
- **`mut` only when you must reassign** — and note a `mut` variable **cannot be
  captured** inside an `each`/`where`/`par-each` closure.
- **`const`** for anything needed at parse time (rule above).

## Custom commands

([custom commands](https://www.nushell.sh/book/custom_commands.html),
[scripts](https://www.nushell.sh/book/scripts.html))

- **Type the parameters and declare the input/output signature.** Types are
  checked at parse time and document the command.

  ```nu
  def increment [value: int]: nothing -> int { $value + 1 }
  def "str stats" []: string -> record { ... }
  ```

- **Return implicitly** — the last expression is the result; there is no
  `return` keyword to write.
- **Model options as `--flags`, optionals with defaults, variadics with
  `...rest`.**
- **A script's entry point is `def main [...]`;** subcommands are
  `def "main sub" [...]`. `main` receives typed CLI arguments.
- **If a command must change the environment or `cd`, declare it `def --env`;**
  otherwise its env mutations are discarded on return (env is block-scoped).

## Control flow

([control flow](https://www.nushell.sh/book/control_flow.html))

- **`if` and `match` are expressions** — assign or pipe their result instead of
  mutating a variable across branches.

  ```nu
  let sign = if $x > 0 { 'pos' } else if $x == 0 { 'zero' } else { 'neg' }
  ```

- **Prefer pipeline iteration** (`each`/`where`/`reduce`) over `for`/`while`:
  it returns values and is dramatically faster (the docs cite ~19 ms vs ~64 s
  over 50k iterations).
- **Parallelize independent per-row work with `par-each`, then `sort`** — order
  is not guaranteed. ([parallelism](https://www.nushell.sh/book/parallelism.html))
- **Sequence with `;`; combine conditions with `and`/`or`** (not Bash's `&&`).
- **Reference pipeline input with `$in`** (it cannot cross a `;` — use a pipe).
  ([pipelines](https://www.nushell.sh/book/pipelines.html))

## Environment and configuration

([configuration](https://www.nushell.sh/book/configuration.html),
[environment](https://www.nushell.sh/book/environment.html))

- **Put settings, commands, and aliases in `config.nu`** (the primary file);
  `env.nu` is legacy and loads first. Drop reusable snippets into an autoload dir
  (`$nu.user-autoload-dirs`) instead of growing `config.nu`.
- **`$env` is block-scoped.** Set with `$env.FOO = ...`; scope a variable to one
  command inline (`FOO=bar some-cmd`) rather than mutating global state.
- **Treat `$env.PATH` as a list** and mutate with `prepend`/`append`, not string
  concatenation.
- **Build and test paths with `path` builtins** (`path join`, `path exists`) so
  separators stay correct cross-platform.

## Modules and overlays

([creating modules](https://www.nushell.sh/book/modules/creating_modules.html),
[overlays](https://www.nushell.sh/book/overlays.html))

- **Package reusable code as a module and `export` only the public surface.**
- **Use `export-env { ... }` for env a module must apply on import** — it runs at
  evaluation, not parse time.
- **Grow into a directory module with `mod.nu`;** name a default command `main`.
- **Use overlays for toggleable, virtual-env-style layers** (`overlay use` /
  `overlay hide`). The path must still be a parse-time constant.

## Error handling

([control flow](https://www.nushell.sh/book/control_flow.html),
[creating errors](https://www.nushell.sh/book/creating_errors.html),
[navigating structured data](https://www.nushell.sh/book/navigating_structured_data.html))

- **Wrap fallible code in `try { } catch {|err| ... }`** and inspect the
  structured error record instead of letting it abort the script.
- **Raise rich errors with `error make`** using `msg` + `label` + `span`
  (from `(metadata $x).span`) so Nushell underlines the offending input.
- **Access maybe-missing cells with an optional path** (`get -o`, or `$x.col?`)
  to get `null` instead of a hard error, then `default` to fill it.

  ```nu
  $data | get temps?.1 | default 0
  ```

## External commands and exit codes

([running externals](https://www.nushell.sh/book/running_externals.html),
[stdout, stderr, exit codes](https://www.nushell.sh/book/stdout_stderr_exit_codes.html))

- **Force an external with `^`** when a builtin shadows it, and **quote its
  arguments** yourself (no word-splitting).

  ```nu
  ^git commit -m "message with spaces"
  ```

- **Capture results with `| complete`** to get `{stdout, stderr, exit_code}` and
  branch on the real status.

  ```nu
  let r = (^git status | complete)
  if $r.exit_code != 0 { print -e $r.stderr }
  ```

- **Tolerate an expected failure with `do -i { ^cmd }` or `try`;** read
  `$env.LAST_EXIT_CODE` when you need the code.

## Version stability

Nushell is pre-1.0 and ships **breaking changes on a roughly six-week cadence** —
for example division began returning floats and `mod` was redesigned in
[0.100.0](https://www.nushell.sh/blog/2024-11-12-nushell_0_100_0.html), and `find`
became case-sensitive by default in
[0.107.0](https://www.nushell.sh/blog/2025-09-02-nushell_0_107_0.html).

- **Declare the Nushell version a script targets** in a header comment, and
  optionally warn at runtime.

  ```nu
  # targets Nushell 0.114
  if (version).version != "0.114.1" { print -e "warning: untested Nu version" }
  ```

- **Do not compare version strings with `<`/`>`** — they compare lexically, so
  `"0.100.0" < "0.99.0"` is true. Match exactly, or parse the components.

## Introspection

Explore commands from inside the shell — and note that `help commands` returns a
**table** you can filter like any other data.
([quick tour](https://www.nushell.sh/book/quick_tour.html))

- `help <command>` or `<command> --help` — documentation for one command.
- `help commands` — every builtin, as a table to `where`/`select`.
- `help --find <text>` — search command docs.
- `help commands | where is_const` — the commands usable at **parse time** (the
  ones allowed in a `const`, or in a `source`/`use` path — see
  [the mental model](#the-mental-model-parse-time-then-run-time)).

## Testing

Static-check every `*.nu` with `nu --ide-check N script.nu`. Because parsing is a
separate stage, it reports parse and type errors as JSON **without executing**
the script — ideal for CI and pre-commit. This repo's `task nushell`
(`tools/check-nushell.sh`) fails on any `"severity":"Error"`.

## Sources

- Nushell Book — <https://www.nushell.sh/book/>
- Nushell release notes — <https://www.nushell.sh/blog/>
- The book is MIT-licensed
  ([nushell/nushell.github.io](https://github.com/nushell/nushell.github.io));
  rules here are summarized, with links back to each source page.

See [`skills/shell`](../skills/shell/) for the agent-facing summary and
[`examples/nushell/`](../examples/nushell/) for parse-clean fragments.

## Invoking `nu` from an agent or a script

Use `-n` (`--no-config-file`). Without it, `nu -c` loads the user's `config.nu` and
`env.nu`, so the command inherits their aliases, `$env`, and any parse-time `source`
— which makes an agent-run command non-deterministic and hostage to a config it did
not write. That is the same parse-time failure documented above, arriving through the
back door.

| Form | Use for |
| --- | --- |
| `nu -n -c '...'` | **agent/CI one-liners** — no config, no env, deterministic |
| `nu -n script.nu` | running a script file without user config |
| `nu --stdin -c '...'` | piping data in; read it via `$in` |
| `nu --no-newline -c '...'` | output destined for command substitution |
| `#!/usr/bin/env nu` | a standalone executable script |
| `nu -l` / `nu -i` | login / interactive shell — a human's shell, not a script's |

Startup cost is small when the config is lean (~35ms vs ~25ms on a tuned machine), so
determinism, not speed, is the reason.

Check a script before shipping it:

```sh
nu --ide-check 0 script.nu   # parse + type errors, no execution
```
