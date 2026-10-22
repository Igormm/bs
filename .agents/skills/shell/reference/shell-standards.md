# Shell standards

A distilled, opinionated baseline for **safe, correct** Bash. Every rule is
enforceable — each carries a rationale and, where a linter catches it, a
ShellCheck code you can look up at
`https://www.shellcheck.net/wiki/SC####`. Style conventions follow the
**Google Shell Style Guide** (`https://google.github.io/styleguide/shellguide.html`),
cited by section name.

How this repo enforces these rules: the example contract
(`tools/check-bad-examples.sh`) runs `shellcheck --severity=style` — the strictest
level, with `enable=all` from `.shellcheckrc` — and asserts that each `*.bad.sh`
triggers its documented code. CI's *linting* of the repo's own clean scripts
(`tools/lint-shell.sh`) uses `--severity=warning`, which catches the
higher-severity codes below (`SC2155`, `SC2206`, `SC2068`, …) but filters out the
lower ones: `SC2086` and `SC2162` are **info** and `SC2006` and `SC2292` are
**style**. So run `shellcheck` at its **default (style)** severity locally to
surface every rule — `--severity=warning` alone will not flag an unquoted
expansion.

## The non-negotiables

### 1. Start every script with strict mode

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e` — exit on any unhandled non-zero status.
- `set -u` — treat an unset variable as an error (catches typos and missing
  arguments). Reference an intentionally-optional variable as `"${VAR:-}"`.
- `set -o pipefail` — a pipeline fails if **any** stage fails, not just the last.
  Without it, `false | true` succeeds and errors vanish.

`set -e` is a floor, not a safety net: it does **not** fire inside a command
whose status is tested (`if`, `&&`, `||`, `!`) or in most command substitutions.
Check the returns that matter explicitly. See Google Shell Style Guide,
*"Checking Return Values."*

> Do not blanket-set `IFS=$'\n\t'`. It changes word-splitting globally and
> surprises later code. Quote your expansions instead (rule 2) and set `IFS`
> locally, only around the one `read`/loop that needs it.

### 2. Quote every expansion — `SC2086` (info)

Unquoted expansions undergo word-splitting and glob expansion. Quote them.

```bash
# bad  — SC2086: splits on whitespace, expands globs in $msg
rm $file
log $msg

# good
rm -- "$file"
log "$msg"
```

Quote command substitutions too (`"$(...)"`), and use `--` before positional
arguments that may begin with `-`. When you *want* a list, use an array (rule 8),
never an unquoted string. Google Shell Style Guide, *"Quoting."*

### 3. Read with `read -r` — `SC2162` (info)

Bare `read` treats a backslash as an escape character, silently mangling paths
and any escaped data. Almost always you want the raw line:

```bash
# bad  — SC2162: "C:\Users\me" becomes "C:Usersme"
while IFS= read line; do process "$line"; done < file

# good
while IFS= read -r line; do process "$line"; done < file
```

`IFS=` keeps leading/trailing whitespace intact.

### 4. Use `[[ ... ]]`, not `[ ... ]` or `test` — `SC2292` (style)

`[[ ]]` is a Bash keyword: no word-splitting or globbing on its operands, and it
adds `=~`, `&&`, `||`, and pattern matching. `[ ]` is an ordinary command whose
unquoted operands split and glob.

```bash
# bad  — empty or multi-word $answer breaks the test
[ $answer = yes ] && proceed

# good
[[ $answer == yes ]] && proceed
```

Use `(( ... ))` for arithmetic conditionals. Google Shell Style Guide,
*"Test, `[ … ]`, and `[[ … ]]`."*

### 5. `$(...)`, never backticks — `SC2006` (style)

`$(...)` nests cleanly and is readable; backticks require backslash-escaping to
nest and are visually noisy. `shfmt` rewrites backticks to `$(...)` on save, so
this one is hard to get wrong once formatting is enforced.

```bash
# bad  — SC2006
now=`date +%s`

# good
now="$(date +%s)"
```

Google Shell Style Guide, *"Command Substitution."*

### 6. Prefer functions with `local`; declare and assign separately — `SC2155` (warning)

Every variable inside a function should be `local` so it cannot leak into the
caller. Assigning a command substitution on the same line as `local` **masks the
command's exit status** (`local` always returns 0):

```bash
# bad  — SC2155: a failing $(...) is hidden; $dir looks fine
local dir="$(mktemp -d)"

# good  — declare, then assign so `set -e` can see a failure
local dir
dir="$(mktemp -d)"
```

Google Shell Style Guide, *"Use Local Variables."*

### 7. Never leave a sourced script with `exit` — use `return`

`exit N` terminates the **caller's** shell when a file is `source`d. A library
or a function must signal failure with `return N` and let the top-level script
decide whether to exit.

```bash
# bad  — kills the interactive shell that sourced this file
command -v jq > /dev/null || exit 1

# good
command -v jq > /dev/null || return 1
```

Reserve `exit` for the top-level `main` of an executable script. Google Shell
Style Guide, *"Function Names"* / *"main."*

### 8. Use arrays for lists and argument vectors — `SC2206`/`SC2068` (warning/error)

A space-separated string cannot represent an element that contains spaces. Build
command arguments as an array and expand it quoted with `"${arr[@]}"`.

```bash
# bad  — one file named "my file.txt" becomes two arguments
flags="-l -a"
files="a.txt my file.txt"
ls $flags $files

# good
flags=(-l -a)
files=(a.txt "my file.txt")
ls "${flags[@]}" "${files[@]}"
```

Read lines into an array with `mapfile -t arr < file` rather than
`arr=($(cat file))` (which splits and globs — `SC2207`). Google Shell Style
Guide, *"Arrays."*

### 9. Clean up with `trap` on `EXIT`

Anything you create (temp dirs, background jobs, lock files) must be released on
every exit path — success, error, or signal. A single `EXIT` trap covers them
all:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# ... use "$tmp" ...
```

Set the trap immediately after creating the resource, so an early failure still
triggers cleanup. Keep the variable at script scope, not `local` inside a
function, or the trap cannot see it after the function returns.

### 10. Do not mask errors with `|| true`

`some_cmd || true` throws away a real failure to keep `set -e` happy. If a
non-zero status is genuinely acceptable, say so explicitly and narrowly:

```bash
# bad  — hides every possible failure of grep, not just "no match"
grep -q pattern file || true

# good  — grep returns 1 for "no match" (fine) but 2 for a real error
if grep -q pattern file; then found=1; else found=0; fi
```

Handle the specific status you expect; let unexpected ones fail. Google Shell
Style Guide, *"Checking Return Values."*

### 11. Minimize subshells and command substitution

Each `$(...)`, pipe stage, and `( ... )` forks a process and discards variable
assignments made inside it. Prefer Bash built-ins:

```bash
# bad  — a subshell per line, and useless use of echo/sed
name=$(echo "$path" | sed 's#.*/##')

# good  — parameter expansion, no fork
name="${path##*/}"
```

Read files with `mapfile`/`read`, transform strings with parameter expansion
(`${var#...}`, `${var/...}`, `${var:-...}`), and reserve external tools for work
the shell genuinely cannot do.

### 12. Print with `printf`, not `echo` — `SC2028`/`SC2059`

`echo`'s handling of `-e`, `-n`, and backslashes varies across sh/bash/zsh/dash
and with the `xpg_echo` option, so its output is not portable. `printf` is
predictable everywhere (and is both a Bash builtin and `/usr/bin/printf`). Keep
data out of the format string.

```bash
# bad  — SC2028: escapes may print literally; SC2059: $msg is used as a format
echo "Name:\t$name"
printf "$msg\n"

# good
printf 'Name:\t%s\n' "$name"
printf '%s\n' "$msg"
```

POSIX itself recommends `printf` over `echo`. See ShellCheck
[SC2028](https://www.shellcheck.net/wiki/SC2028) and
[SC2059](https://www.shellcheck.net/wiki/SC2059).

### 13. Brace your expansions: `${var}` — `SC2250`

Braces are **required** for `${var}_suffix`, `${arr[@]}`, `${var:-default}`, and
multi-digit positionals (`${10}`). Beyond that, always-bracing is a defensible
house style (this repo enables it via `SC2250` under `enable=all`) because it
removes the "is the next character part of the name?" question. The Google Shell
Style Guide ranks **quoting first**, then prefers `"${var}"` over `"$var"`, and
exempts single-character specials (`$1`, `$?`, `$$`).

```bash
# bad  — $partial_version is a different (unset) variable
url="host/$partial_version/x"
# good
url="host/${partial}_version/x"
```

### 14. Make constants `readonly`

Mark values that must not change (and environment-derived config) `readonly` (or
`declare -r`), so an accidental reassignment fails loudly. Google Shell Style
Guide, *"Constants."*

```bash
readonly MAX_RETRIES=5
```

### 15. Check commands with `command -v`, not `which`

`which` is an external program with non-portable output and an unreliable exit
status; `command -v` is POSIX and built in.
([BashFAQ/081](https://mywiki.wooledge.org/BashFAQ/081))

```bash
command -v jq > /dev/null || { printf 'jq is required\n' >&2; exit 1; }
```

### 16. Never parse `ls` — glob or use `find -print0` — `SC2045`/`SC2012`

`ls` output is for humans; parsing it breaks on spaces, newlines, and control
characters in filenames. Use a glob, or `find … -print0` with
`mapfile -d ''`. (Iterating `ls` triggers `SC2045`; using `ls` where `find`
belongs triggers `SC2012`.)
([ParsingLs](https://mywiki.wooledge.org/ParsingLs))

```bash
# bad  — SC2045
for f in $(ls *.txt); do ...; done
# good
for f in ./*.txt; do ...; done
```

### 17. Fail fast on a required variable with `${var:?message}`

`${VAR:?msg}` aborts with `msg` on stderr if `VAR` is unset or empty — a concise
companion to `set -u`.

```bash
: "${API_TOKEN:?set API_TOKEN in the environment}"
```

> Strict-mode addendum (rule 1): add `set -E` (`errtrace`) when you use a
> `trap … ERR`, or the trap will not fire inside functions, subshells, or
> command substitutions.

## Portability note

These rules target **Bash** (`#!/usr/bin/env bash`), not POSIX `sh`. `[[ ]]`,
arrays, `local`, and `mapfile` are Bash features. If a script must run under
`sh`, drop to POSIX constructs and validate with `shellcheck --shell=sh`. macOS
ships Bash 3.2, so avoid Bash 4+ features (`declare -A`, `mapfile`, `${var,,}`)
in scripts that must run there — see `reference/bash.md`.

## Sources

- Google Shell Style Guide — `https://google.github.io/styleguide/shellguide.html`
- ShellCheck wiki (per-code pages) — `https://www.shellcheck.net/wiki/`
- Bash reference manual —
  `https://www.gnu.org/software/bash/manual/bash.html`

See `skills/shell-standards/SKILL.md` for the agent-facing summary and
`examples/standards/` for a runnable good/bad pair per rule with a ShellCheck
code.
