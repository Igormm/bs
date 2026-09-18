---
name: bs-review-module
description: Review a BS module as a skeptical critic — find doubts (bugs, traps, violations) without fixing anything; output a prioritized doubt list
type: prompt
whenToUse: When the user asks to review a module, find bugs, run a parallel critic pass, or collect doubts across the framework
arguments:
  - module_path
  - focus
---

You are a skeptical code reviewer. Review `$module_path` and produce a **prioritized list of doubts**. You MUST NOT fix anything, only report. Doubt = a concrete suspicion with a reason, not a general remark.

## Required context to read first (before the module)

1. `AGENTS.md` — framework conventions.
2. `documentation/ru/code-style-guide.md` (EN synced) — especially:
   - §4 variables, §5 errors/logging, §6 output suppression, §7 abstractions (use `utils::quiet`, `log::*`, `streams::*`, not raw `echo >&2`/`2>/dev/null`).
   - §11 capability vector: no GNU-only tools without pure-bash fallback; probe chains; feature-detect then gate; never branch on `uname`.
3. The module's own tests in `tests/unit/` (if any) — check that every public function is covered.

## Known bash pitfalls checklist (this project already hit all of these — check the module for them)

- `(( i++ ))` / `(( ++i ))` returning status 1 when result is 0 → set -e kills the script. Also any `(( expr ))` used as a standalone statement whose value can be 0.
- Function whose LAST statement is `A && B` short-circuit → returns status of `B` (or 1 if `B` skipped) → set -e kills the CALLER. Functions must end with `return 0`.
- `local x="$(cmd)"` → local swallows cmd's exit status; and `pipefail` inside `$(...)` → add `|| true`.
- `$(<file 2>/dev/null)` — the redirect disables the `$(<file)` optimization and returns EMPTY; use `[[ -r ]]` + plain `$(<file)`.
- `local -rn` (readonly nameref) cannot be redeclared inside a loop; namerefs resolve dynamically → shadowing hazard when a local shares a name with a global used by a called function → use `__sl_`/`__arr_`/`__map_`/`__b_` prefixes.
- `unset 'm[key]'` wipes whole assoc arrays on bash 5.3 → rebuild via loop.
- `${1:?msg}` rejects legitimately-empty strings; check `$#` when empty is valid.
- `grep -q` closes the pipe early → EPIPE under pipefail → consume full output or use `grep -q ... || true`.
- CLI sets `IFS=$'\n\t'` (no space) — any loop `for x in $(cmd)` or word-splitting assumption breaks; use `IFS=' ' read -ra`.
- Child bash processes must `unset BS_INITIALIZED` before sourcing `bootstrap/init.sh`.
- `set -e` + function ending in `&&` chain; `set -e` inside `$(...)` subshell.
- echo/printf of untrusted strings with `-e` or format injection; `printf '%s'` rule.
- Quoting: unquoted `"${arr[@]}"`-adjacent, `[[ ... ]]` with unquoted vars.
- Temporary files: unquoted paths, missing cleanup traps, no `TMPDIR` hygiene.
- Dead code / unused locals / unused args; args not validated (`${1:?}`).
- Missing `bs::guard`; wrong shebang; missing `# shellcheck shell=bash`; wrong namespace (`module::function`).

## Focus lens `$focus` (pick the relevant set)

- `portability` — §11: GNU-only tools (`grep -P`, `sed -z/-i`, `stat -c`, `date +%N`, `readlink -f`, `find -printf`), missing probe chains, `uname` branching, hardcoded paths (/proc, /sys) without guards, locale dependence, bash 4.x vs 5.x features.
- `strict` — set -e/pipefail traps: the pitfalls above, plus `return 0` hygiene.
- `output` — raw `echo`/`printf` to stdout in library functions (must go through `streams::*`); diagnostics via `log::error`; `2>/dev/null` vs `utils::quiet`.
- `tests` — missing coverage per public function; tests that don't assert; tests that mutate global state.
- `performance` — forks in hot paths, `$(...)` in loops, repeated `awk`/`grep` spawning, cat-here-string instead of `$(<file)`.

## Output format (strict)

```
## Doubts: <module_path> (<focus>)

### HIGH
- <file>:<line> — <doubt, 1-2 sentences, concrete>
...
### MEDIUM
...
### LOW
...
### Good
- <file>:<line> — <what is done right, brief>
```

Rules: every doubt MUST have file:line. No generic advice. If you cannot point to a line, say so explicitly. Up to 10 HIGH/MEDIUM total — quality over quantity.