# Standards examples

Runnable good/bad pairs for the core rules in
[`reference/shell-standards.md`](../../reference/shell-standards.md). Read the
paired files side by side.

## The contract

- **`*.good.sh`** — the correct pattern. Self-contained, takes no arguments, runs
  to completion with **exit 0**, and is clean under `shellcheck --severity=warning`
  and `shfmt`. Anything that touches the filesystem uses `mktemp` + a `trap`.
  Verified by the behavioural test suite (`tests/examples.bats`).
- **`*.bad.sh`** — the anti-pattern, and **safe to run**: it demonstrates
  incorrectness, never danger. Each carries one directive line —
  `# expect-shellcheck: SC####` (codes ShellCheck must report) or
  `# expect-shellcheck: none` (a style-guide-only pitfall ShellCheck cannot
  catch). Verified by `tools/check-bad-examples.sh`.

## The pairs

| Pair | Good shows | Bad shows | Code |
|------|-----------|-----------|------|
| `01-quote-expansions` | quoting keeps a spaced filename intact | unquoted expansion word-splits | `SC2086` |
| `02-read-r` | `read -r` preserves backslashes | bare `read` mangles them | `SC2162` |
| `03-declare-and-assign` | declare `local`, then assign | `local x="$(cmd)"` hides failure | `SC2155` |
| `04-arrays-not-strings` | arrays hold spaced elements | a string cannot | `SC2206` |
| `05-prefer-double-bracket` | `[[ ]]` survives an empty value | `[ ]` breaks on it | `SC2292` |
| `06-return-not-exit` | helper `return`s | helper `exit`s the caller | none |
| `07-printf-not-echo` | `printf '%s\n' "$x"` | `echo` escapes + var-in-format | `SC2028`/`SC2059` |
| `08-brace-expansions` | `${base}_2026` | `$base_2026` (a different var) | `SC2250` |
| `09-no-parse-ls` | glob `"$dir"/*.txt` | `$(ls *.txt)` | `SC2045` |
| `10-parameter-expansion-not-sed` | `${path##*/}` strips in-process | `echo ... \| sed ...` forks twice | `SC2001` |
| `11-command-v-not-which` | `command -v jq` checks a command | `which jq` is non-standard | `SC2230` |

## `.env.example`

`.env.example` in this directory is a tracked template for environment files. The
convention it teaches: keep real secrets in a git-ignored `.env` (or a secret
manager), commit only a blank-valued example, and read values in scripts with a
safe default — `port="${APP_PORT:-8080}"` — so `set -u` does not abort on an
unset variable.

## Run them

```sh
# One good example:
bash examples/standards/01-quote-expansions.good.sh

# The whole contract (behaviour + linters):
task ci
```

There is deliberately no backticks example: `shfmt` rewrites legacy backticks to
`$(...)` on save, so the anti-pattern cannot survive a formatted file — which is
itself the lesson. Use `$(...)`.
