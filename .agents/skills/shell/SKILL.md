---
name: shell
description: >-
  Load before running or writing ANY shell — including throwaway one-liners you
  intend to run yourself, not just scripts you save. Trigger on the act, not the
  request: you are about to type awk, sed, cut, or a second pipe; you are parsing
  du/ps/ls/find output; a command needs a loop, a conditional, or arithmetic; you are
  writing $(...) inside another $(...); you need a file list, sizes, or process info;
  you are choosing a shebang or an interpreter; a command exceeds one line or will
  outlive this session; output must be machine-read, or must separate data from
  diagnostics; you are editing a Makefile recipe, Dockerfile RUN, CI run: block, cron
  entry, or .env; or you are reviewing or debugging shell someone else wrote. Answers
  "should this be shell at all?" first — usually jq, yq, sd, nu, Python or bun — then
  applies the Bash/Zsh/POSIX/Nushell safety rules to whatever survives that question.
---

# Shell

**Most "shell problems" are solved by not writing shell.** This skill decides that
first, then enforces the rules for the parts that genuinely are shell.

## 1. Pick the tool before writing a line

| The task | Use | Not |
| --- | --- | --- |
| JSON in, JSON out | `jq` | `grep`/`sed` on JSON |
| YAML / TOML / XML | `yq` | any regex |
| Substitute text in files | `sd` | `sed -i` (delimiter escaping, BSD-vs-GNU `-i`) |
| Find files | `fd` | `find` with `-exec` chains |
| Search contents | `rg` | `grep -r` |
| Query the OS for **structured** facts (sizes, processes, files) | `nu` | `du`/`ps` + `awk` |
| String case/encoding transforms | `sttr` | `tr`/`awk` |
| SQLite | `sqlite3` or a `bun` script | shelling out per row |
| Anything with a data structure, two stages of logic, or arithmetic | **Python or a `bun` .ts file** | a pipeline |

**Hard stop:** if a pipeline needs three or more stages, or any `awk` beyond
`{print $1}`, stop and write a script file. A three-stage `awk`/`sed`/`cut` chain is
unreadable, unportable (BSD vs GNU), and silently wrong on unusual input.

See [`reference/pipelines.md`](reference/pipelines.md) for the replacement
table, BSD-vs-GNU traps, and worked rewrites.

## 1b. Do not invoke a tool from memory — check it

**A recalled flag is a guess.** Model memory for CLI flags is stale, version-skewed,
and confidently wrong. Checking costs one command; guessing costs a silent wrong
answer, which is worse than an error because nothing tells you.

Escalate in this order, stopping as soon as you know:

1. **`<cmd> --help`** — always first. Fast, offline, matches the *installed* version.
   Modern Rust tools (`sd`, `rg`, `fd`) have excellent `--help`.
2. **`man <cmd>`** — when `--help` is a summary and you need semantics. Not every tool
   ships one (`nu` and `sttr` do not; `sd`, `rg`, `fd`, `jq`, `yq` do —
   check with `man -w <cmd>`).
3. **`<cmd> --version` + context7** — for a library or a tool with real documentation,
   when behaviour differs across versions. Pin the answer to the installed version.
4. **Web search** — last, for "why does X do Y" questions no reference answers.

Then **run it once on a known input** before trusting it in a pipeline.

Cached essentials and the gotchas that bite —
[`reference/cli-cheatsheets.md`](reference/cli-cheatsheets.md).

## 2. Pick the interpreter deliberately

Never write bare `bash` and hope. On macOS `/bin/bash` is **3.2** (2007, frozen over
GPLv3) — no `mapfile`, no associative arrays, no `${var^^}`. Homebrew's bash 5.x lives
at `/opt/homebrew/bin/bash`.

- Portable script → `#!/usr/bin/env bash` **and** stay inside 3.2 features, or assert
  the version at the top.
- Need bash 4+/5 features → require it explicitly, do not assume `env` finds it.
- Interactive-shell config → that is Zsh on macOS, not bash.
- Structured data → Nushell.

Details and the `env -S` flag trick: [`reference/shebang.md`](reference/shebang.md).

## 3. The non-negotiables (Bash)

| # | Rule | Enforced by |
|---|------|-------------|
| 1 | `set -euo pipefail` first line of every script | style |
| 2 | Quote every expansion: `"$var"`, `"$(cmd)"` | `SC2086` |
| 3 | `read -r`, never bare `read` | `SC2162` |
| 4 | Declare `local`, then assign — `local x="$(cmd)"` hides the exit status | `SC2155` |
| 5 | Arrays for lists; expand `"${arr[@]}"` | `SC2206` |
| 6 | `[[ ... ]]`, not `[ ... ]` | `SC2292` |
| 7 | `return` in helpers; `exit` only in `main` | style |
| 8 | `trap '...' EXIT` for cleanup | style |
| 9 | `printf`, never `echo` — builtins disagree on `-n`, `-e`, backslashes | `SC2028`/`SC2059` |
| 10 | `${var}` braces | `SC2250` |
| 11 | `readonly` constants; `command -v`, not `which` | style |
| 12 | Never parse `ls`; use a glob | `SC2045` |
| 13 | No nested `$( $( ) )` — assign an intermediate variable | readability |

Full rationale and citations: [`reference/shell-standards.md`](reference/shell-standards.md).

## 4. Then the shell-specific reference

Load only the one you are actually writing:

- **Bash** — `pipefail` semantics, `trap ERR`, BSD-vs-GNU coreutils, bash-3.2 traps →
  [`reference/bash.md`](reference/bash.md)
- **Zsh** — `emulate -L zsh`, no automatic word-splitting, glob qualifiers, startup
  files → [`reference/zsh.md`](reference/zsh.md)
- **POSIX sh** — no `local`, no arrays, `[ ]` only, `set -eu` without `pipefail` →
  [`reference/posix-sh.md`](reference/posix-sh.md)
- **Nushell** — parse-time vs runtime, `const` for `source`, structured pipelines,
  `save` not `>`, `^cmd | complete` → [`reference/nushell.md`](reference/nushell.md)
- **Streams** — stdout is data, stderr is diagnostics, exit codes, signals →
  [`reference/streams.md`](reference/streams.md)

## 5. Verify before claiming it works

```bash
shellcheck script.sh          # default severity — CI's --severity=warning hides SC2086
shfmt -d script.sh            # layout, and rewrites backticks
nu --ide-check script.nu      # parse + type errors for Nushell
```

`task lint` runs these across the repo. A script that has not been shellcheck'd at
default severity has not been checked.
