---
name: bs-check-ansi
description: Verify ANSI escape usage across the whole project — no literal '\033' text in printf %s args (broken colors), correct $'\033' ANSI-C quoting, no fragile echo -e, printf format-string escapes accepted
type: prompt
whenToUse: After any change to color/log output (core/logger.sh, core/const.sh, lib/ui/*, update/uninstall messages), before committing output-related code, or when the user reports literal \033[90m text instead of colors
arguments:
  - scope
---

Check `${scope}` (default: `core lib bs install bootstrap examples` — the whole project) for ANSI escape usage. The automated scanner is the ground truth; run it first:

```bash
bash .agents/skills/bs-check-ansi/scripts/check_ansi.sh          # whole project
bash .agents/skills/bs-check-ansi/scripts/check_ansi.sh core lib # narrower scope
```

# Why this check exists

`printf '%s' '\033[90m'` prints the LITERAL text `\033[90m` — printf interprets
escapes only in the format string, never in `%s` arguments. This broke all
colored output in `bs update` (fixed in `34a9f7b`). The project convention:
ANSI-C quoting `$'\033[90m'` (as in `lib/ui/presentation.sh`) or the escape in
a printf format string `printf '\033[90m'`.

# Pattern classes

| Class | Pattern | Verdict |
| --- | --- | --- |
| A1 | `'\033` in plain single quotes (no `$` before) | **CRITICAL** — `printf %s` prints literal `\033` text |
| A2 | `printf '%s' '\033...'` — escape passed as `%s` arg | **CRITICAL** — same broken output |
| B1 | `echo -e "...'\033..."` | WARN — works but depends on `xpg_echo`; prefer `printf` |
| C1 | `printf '\033[90m'` (escape in format string) | OK — printf interprets it |
| C2 | `$'\033[90m'` (ANSI-C quoting) | OK — the project convention |

# Fixing rules

- Replace `'\033[...'` with `$'\033[...'` (ANSI-C quoting) — single-character change, works in bash 4+.
- Or move the escape into the printf format string: `printf '\033[90m%s\033[0m\n' "text"`.
- Never pass an escape as a `%s`/`%b` argument in plain quotes.
- Constants in `core/const.sh` (`COLOR_*`) and `lib/ui/presentation.sh` (`PRESENTATION_COLOR_*`) must use `$'\033'`; code consuming `COLOR_*` via `echo -e` is a WARN (works today, fragile).
- Also verify with `xxd` when unsure: `1b 5b` = real ESC; `5c 30 33 33` = literal `\033` text.

# Verify the actual output

```bash
BS_LOG_COLOR=always ./bs update --system 2>&1 | xxd | head -3   # expect 1b 5b
```

First byte must be `1b` (ESC), never `5c` (backslash).

# Output format

```
## bs-check-ansi: <scope>
CRITICAL <file>:<line> — ...   (only these fail the check)
WARN     <file>:<line> — ...
OK       ...

## Verdict: PASS | FAIL (CRITICAL patterns found — fix with $'\033')
```